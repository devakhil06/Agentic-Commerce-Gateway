"""Durable enrichment jobs and scheduled reconciliation; Redis is optional locally."""

import asyncio

from celery import Celery
from sqlalchemy import select, text

from .agents import enrich
from .config import get_settings
from .db import Merchant, Record, SessionLocal, audit, now
from .payments import reconcile
from .repository import records

settings = get_settings()
celery = Celery("acg", broker=settings.redis_url or "memory://")
celery.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    beat_schedule={"assurance": {"task": "acg.maintain", "schedule": 60.0}},
)


def lock(db, merchant):
    if db.bind.dialect.name == "sqlite":
        db.execute(text("BEGIN IMMEDIATE"))
    else:
        db.execute(select(Merchant).where(Merchant.id == merchant).with_for_update()).scalar_one()


@celery.task(name="acg.enrich")
def process_job(job_id):
    with SessionLocal() as db:
        job = db.get(Record, job_id)
        if not job or job.data["status"] == "COMPLETED":
            return
        merchant = job.merchant_id
        identifiers = job.data["product_ids"]
        job.data = {**job.data, "status": "RUNNING", "started_at": now()}
        db.commit()
        try:
            # Enrichment is non-financial; the core purchase path never waits on it.
            asyncio.run(enrich(db, merchant, identifiers))
            job.data = {**job.data, "status": "COMPLETED", "completed_at": now()}
            db.commit()
        except Exception:
            db.rollback()
            job = db.get(Record, job_id)
            job.data = {
                **job.data,
                "status": "FAILED",
                "error": "Enrichment failed; queued job can be retried.",
            }
            db.commit()


def dispatch_job(job_id):
    if settings.redis_url:
        process_job.delay(job_id)
    else:
        process_job(job_id)


@celery.task(name="acg.maintain")
def maintain():
    with SessionLocal() as db:
        merchant_ids = list(db.scalars(select(Merchant.id)))
    for merchant in merchant_ids:
        with SessionLocal() as db:
            lock(db, merchant)
            pending = [
                r
                for r in records(db, merchant, "order")
                if r.data["state"] in ("PAYMENT_PENDING", "RECONCILIATION_REQUIRED")
            ]
            for order in pending:
                try:
                    asyncio.run(reconcile(db, merchant, order.id))
                except Exception:
                    audit(db, merchant, "reconciliation.retry_scheduled", reference=order.id)
            active_quotes = {
                r.data["quote_id"]
                for r in records(db, merchant, "order")
                if r.data["state"] in ("ORDER_CREATED", "PAYMENT_PENDING", "RECONCILIATION_REQUIRED")
            }
            for quote in records(db, merchant, "quote"):
                if (
                    quote.data["status"] == "RESERVED"
                    and quote.data["reservation_expires_at"] <= now()
                    and quote.id not in active_quotes
                ):
                    quote.data = {**quote.data, "status": "RELEASED"}
                    audit(db, merchant, "inventory.reservation_expired", reference=quote.id)
            for session in records(db, merchant, "session"):
                if session.data.get("expires_at", 0) <= now() and session.data.get("history"):
                    session.data = {"history": [], "intent": {}, "expires_at": 0}
            db.commit()
    with SessionLocal() as db:
        jobs = list(db.scalars(select(Record).where(Record.kind == "job")))
        retry_ids = [
            j.id
            for j in jobs
            if j.data["status"] == "QUEUED"
            or (j.data["status"] == "RUNNING" and j.data.get("started_at", 0) < now() - 1800)
        ]
    for job_id in retry_ids:
        process_job.delay(job_id)
