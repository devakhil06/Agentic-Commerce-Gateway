"""Razorpay adapter and deterministic transaction engine. Amounts are INR paise."""

import hashlib
import hmac
import json
from typing import Protocol

import httpx
from fastapi import HTTPException

from .auth import decrypt
from .commerce import availability, load_lines
from .config import get_settings
from .db import Merchant, audit, now
from .policies import evaluate, policy_for
from .repository import by_key, create, get_record, pack, records


def credentials(db, merchant):
    value = decrypt(db.get(Merchant, merchant).credentials)
    settings = get_settings()
    # Environment credentials are intentionally a single-workspace development option.
    if not value and settings.environment == "development":
        value = {
            "key_id": settings.razorpay_key_id,
            "key_secret": settings.razorpay_key_secret,
            "webhook_secret": settings.razorpay_webhook_secret,
        }
    return value


class PaymentProvider(Protocol):
    async def create_order(self, amount: int, receipt: str) -> dict: ...
    async def payment(self, identifier: str) -> dict: ...
    async def order_payments(self, identifier: str) -> list: ...


class Razorpay:
    def __init__(self, keys):
        self.keys = keys
        if not keys.get("key_id", "").startswith("rzp_test_") or not keys.get("key_secret"):
            raise HTTPException(503, "Connect Razorpay test credentials in Settings to start checkout")

    async def request(self, method, path, payload=None):
        async with httpx.AsyncClient(
            timeout=15, auth=(self.keys["key_id"], self.keys["key_secret"])
        ) as client:
            response = await client.request(method, "https://api.razorpay.com/v1" + path, json=payload)
            response.raise_for_status()
            return response.json()

    async def create_order(self, amount, receipt):
        return await self.request(
            "POST",
            "/orders",
            {
                "amount": amount,
                "currency": "INR",
                "receipt": receipt,
                "notes": {"internal_order_id": receipt},
                "partial_payment": False,
            },
        )

    async def payment(self, identifier):
        if not identifier.startswith("pay_") or not identifier.replace("_", "").isalnum():
            raise HTTPException(422, "Invalid payment identifier")
        return await self.request("GET", "/payments/" + identifier)

    async def order_payments(self, identifier):
        if not identifier.startswith("order_") or not identifier.replace("_", "").isalnum():
            raise HTTPException(422, "Invalid provider order identifier")
        return (await self.request("GET", "/orders/" + identifier + "/payments")).get("items", [])


TRANSITIONS = {
    "ORDER_CREATED": {"PAYMENT_PENDING", "RECONCILIATION_REQUIRED"},
    "PAYMENT_PENDING": {"PAYMENT_CAPTURED", "PAYMENT_FAILED", "RECONCILIATION_REQUIRED"},
    "PAYMENT_FAILED": {"PAYMENT_PENDING", "PAYMENT_CAPTURED", "RECONCILIATION_REQUIRED"},
    "RECONCILIATION_REQUIRED": {"PAYMENT_PENDING", "PAYMENT_CAPTURED", "PAYMENT_FAILED"},
    "PAYMENT_CAPTURED": {"ORDER_CONFIRMED"},
    "ORDER_CONFIRMED": {"FULFILLMENT_PENDING"},
    "FULFILLMENT_PENDING": {"COMPLETED"},
    "COMPLETED": set(),
}


def transition(db, order, target, reason):
    current = order.data["state"]
    if current == target:
        return
    if target not in TRANSITIONS.get(current, set()):
        audit(
            db,
            order.merchant_id,
            "transaction.invalid_transition",
            reference=order.id,
            before=current,
            target=target,
        )
        raise HTTPException(409, f"Invalid transition {current} → {target}")
    order.data = {**order.data, "state": target, "updated_at": now()}
    audit(
        db,
        order.merchant_id,
        "transaction." + target.lower(),
        reference=order.id,
        before=current,
        after=target,
        reason=reason,
    )


def checkout_payload(order, key_id):
    return {**pack(order), "key_id": key_id, "currency": "INR", "test_mode": True}


async def checkout(db, merchant, request):
    keyed = by_key(db, merchant, "idempotency", request.idempotency_key)
    if keyed and keyed.data["quote_id"] != request.quote_id:
        raise HTTPException(409, "Idempotency key was already used for another quote")
    existing = by_key(db, merchant, "order", request.quote_id)
    keys = credentials(db, merchant)
    if existing:
        if not keyed:
            create(
                db,
                merchant,
                "idempotency",
                {"quote_id": request.quote_id, "order_id": existing.id},
                key=request.idempotency_key,
            )
        return checkout_payload(existing, keys.get("key_id", ""))
    provider = Razorpay(keys)
    quote = get_record(db, merchant, "quote", request.quote_id)
    data = quote.data
    if data["status"] != "RESERVED" or min(data["expires_at"], data["reservation_expires_at"]) <= now():
        raise HTTPException(409, "Quote or stock reservation expired; request a new offer")
    products = load_lines(db, merchant, data["lines"])
    if any(p.price != data["prices"][p.id] for p in products):
        raise HTTPException(409, "Catalog prices changed; request a new quote")
    check = evaluate(
        policy_for(db, merchant),
        products,
        data["lines"],
        data["total"],
        availability(db, merchant, quote.id),
        data.get("override"),
        data.get("delivery_days"),
    )
    if check["decision"] != "ALLOW":
        raise HTTPException(409, check)
    order = create(
        db,
        merchant,
        "order",
        {
            "quote_id": quote.id,
            "session_id": data["session_id"],
            "negotiation_id": data["negotiation_id"],
            "state": "ORDER_CREATED",
            "amount": data["total"],
            "currency": "INR",
            "product_names": data["product_names"],
            "razorpay_order_id": None,
            "razorpay_payment_id": None,
            "updated_at": now(),
        },
        key=quote.id,
    )
    create(
        db, merchant, "idempotency", {"quote_id": quote.id, "order_id": order.id}, key=request.idempotency_key
    )
    audit(db, merchant, "transaction.order_created", reference=order.id, quote_id=quote.id, policy=check)
    # Persist an attempt BEFORE crossing the provider boundary. A timeout/crash can
    # never make a second create-order request for the same quote.
    db.commit()
    try:
        result = await provider.create_order(data["total"], order.id)
        if (
            result.get("amount") != data["total"]
            or result.get("currency") != "INR"
            or not result.get("id", "").startswith("order_")
        ):
            raise ValueError("Unexpected provider order response")
        order.data = {**order.data, "razorpay_order_id": result["id"]}
        transition(db, order, "PAYMENT_PENDING", "Razorpay test order created")
    except (httpx.HTTPError, ValueError):
        transition(
            db,
            order,
            "RECONCILIATION_REQUIRED",
            "Provider response uncertain; do not create another payment attempt",
        )
        order.data = {
            **order.data,
            "failure_reason": "Provider order creation could not be confirmed. Recover the provider order reference before retrying.",
        }
    db.commit()
    return checkout_payload(order, keys["key_id"])


def signature_valid(secret, payload, signature):
    return hmac.compare_digest(hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest(), signature)


def capture(db, order, payment):
    data = order.data
    if (
        payment.get("order_id") != data["razorpay_order_id"]
        or payment.get("amount") != data["amount"]
        or payment.get("currency") != "INR"
        or payment.get("status") != "captured"
    ):
        raise HTTPException(409, "Payment amount, currency, order or capture status does not match")
    if data["state"] in ("ORDER_CONFIRMED", "FULFILLMENT_PENDING", "COMPLETED"):
        if data["razorpay_payment_id"] != payment["id"]:
            audit(
                db,
                order.merchant_id,
                "payment.extra_capture_requires_review",
                reference=order.id,
                payment_id=payment["id"],
            )
        return pack(order)
    quote = get_record(db, order.merchant_id, "quote", data["quote_id"])
    products = load_lines(db, order.merchant_id, quote.data["lines"])
    stock = availability(db, order.merchant_id, quote.id)
    if any(stock.get(p.id, 0) < line["quantity"] for p, line in zip(products, quote.data["lines"])):
        order.data = {
            **data,
            "razorpay_payment_id": payment["id"],
            "failure_reason": "Payment captured but inventory needs merchant intervention",
        }
        if data["state"] != "RECONCILIATION_REQUIRED":
            transition(
                db,
                order,
                "RECONCILIATION_REQUIRED",
                "Captured payment has an inventory exception; do not charge again",
            )
        return pack(order)
    order.data = {**data, "razorpay_payment_id": payment["id"], "signature_verified": True}
    transition(db, order, "PAYMENT_CAPTURED", "Capture verified server-side")
    for product, line in zip(products, quote.data["lines"]):
        product.stock -= line["quantity"]
    q = quote.data
    standard = sum(q["prices"][line["product_id"]] * line["quantity"] for line in q["lines"])
    cross_sell = sum(
        q["prices"][line["product_id"]] * line["quantity"]
        for line in q["lines"]
        if line["kind"] == "cross_sell"
    )
    upsell = max(0, standard - cross_sell - q["baseline"])
    discount = standard - q["total"]
    attribution = {
        "baseline": q["baseline"],
        "upsell": upsell,
        "cross_sell": cross_sell,
        "discount": discount,
        "final_revenue": q["total"],
        "incremental": q["total"] - q["baseline"],
        "method": "attribution-v1",
    }
    order.data = {**order.data, "attribution": attribution}
    quote.data = {
        **q,
        "status": "CONSUMED",
        "override": {**q["override"], "consumed": True} if q.get("override") else None,
    }
    transition(
        db, order, "ORDER_CONFIRMED", "Inventory consumed and revenue attribution recorded exactly once"
    )
    return pack(order)


async def verify(db, merchant, request):
    order = get_record(db, merchant, "order", request.order_id)
    keys = credentials(db, merchant)
    provider_order = order.data.get("razorpay_order_id")
    if not provider_order:
        raise HTTPException(409, "Provider order is not confirmed")
    if not signature_valid(
        keys.get("key_secret", ""),
        f"{provider_order}|{request.razorpay_payment_id}".encode(),
        request.razorpay_signature,
    ):
        raise HTTPException(400, "Invalid payment signature")
    payment = await Razorpay(keys).payment(request.razorpay_payment_id)
    return capture(db, order, payment)


async def reconcile(db, merchant, order_id):
    order = get_record(db, merchant, "order", order_id)
    if not order.data.get("razorpay_order_id"):
        return {
            **pack(order),
            "action_required": "Recover the Razorpay order using the internal order ID as receipt. Use the recovery endpoint; no new charge is attempted.",
        }
    payments = await Razorpay(credentials(db, merchant)).order_payments(order.data["razorpay_order_id"])
    for payment in payments:
        if payment.get("status") == "captured":
            result = capture(db, order, payment)
            audit(db, merchant, "transaction.reconciled", reference=order.id, payment_id=payment["id"])
            return result
    if (
        payments
        and all(p.get("status") == "failed" for p in payments)
        and order.data["state"] in ("PAYMENT_PENDING", "RECONCILIATION_REQUIRED")
    ):
        transition(db, order, "PAYMENT_FAILED", "All provider payment attempts failed")
        order.data = {**order.data, "failure_reason": "Payment failed. Revalidate the quote before retrying."}
    return pack(order)


async def webhook(db, merchant, raw, signature, event_id):
    keys = credentials(db, merchant)
    if not keys.get("webhook_secret") or not signature_valid(keys["webhook_secret"], raw, signature):
        raise HTTPException(400, "Invalid webhook signature")
    dedup_key = event_id or hashlib.sha256(raw).hexdigest()
    existing = by_key(db, merchant, "webhook", dedup_key)
    if existing:
        return {"status": "duplicate"}
    event = json.loads(raw)
    payment = event.get("payload", {}).get("payment", {}).get("entity", {})
    order = next(
        (
            r
            for r in records(db, merchant, "order")
            if r.data.get("razorpay_order_id") == payment.get("order_id") and payment.get("order_id")
        ),
        None,
    )
    if not order and payment.get("order_id"):
        # Do not acknowledge a valid event prematurely: reconciliation may still
        # be persisting the provider order reference. Razorpay should retry.
        raise HTTPException(503, "Provider order is not linked yet; retry event")
    if order and event.get("event") == "payment.captured":
        capture(db, order, payment)
    elif order and event.get("event") == "payment.failed":
        # A failed *attempt* cannot downgrade a paid order or prove the whole
        # checkout failed. Reconciliation examines all provider attempts.
        audit(
            db,
            merchant,
            "payment.attempt_failed",
            reference=order.id,
            payment_id=payment.get("id"),
            reason=payment.get("error_description", "Payment attempt failed"),
        )
    create(
        db,
        merchant,
        "webhook",
        {"event": event.get("event"), "order_id": order.id if order else None},
        key=dedup_key,
    )
    return {"status": "processed"}
