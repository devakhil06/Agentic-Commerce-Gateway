from fastapi import HTTPException
from sqlalchemy import select

from .db import Record


def records(db, merchant, kind):
    return list(
        db.scalars(
            select(Record)
            .where(Record.merchant_id == merchant, Record.kind == kind)
            .order_by(Record.created_at.desc())
        )
    )


def get_record(db, merchant, kind, identifier):
    record = db.scalar(
        select(Record).where(Record.id == identifier, Record.merchant_id == merchant, Record.kind == kind)
    )
    if not record:
        raise HTTPException(404, f"{kind.replace('_', ' ').title()} not found")
    return record


def by_key(db, merchant, kind, key):
    return db.scalar(
        select(Record).where(Record.merchant_id == merchant, Record.kind == kind, Record.key == key)
    )


def create(db, merchant, kind, data, key=None):
    row = Record(merchant_id=merchant, kind=kind, data=data, key=key)
    db.add(row)
    db.flush()
    return row


def pack(row):
    return {"id": row.id, "created_at": row.created_at, **row.data}
