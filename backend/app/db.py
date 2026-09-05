from datetime import datetime, timezone
from uuid import uuid4

from pgvector.sqlalchemy import Vector
from sqlalchemy import JSON, ForeignKey, Integer, String, UniqueConstraint, create_engine, event
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from .config import get_settings


def uid():
    return str(uuid4())


def now():
    return int(datetime.now(timezone.utc).timestamp())


class Base(DeclarativeBase):
    pass


class Merchant(Base):
    __tablename__ = "merchants"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    name: Mapped[str] = mapped_column(String(120))
    store_type: Mapped[str] = mapped_column(default="custom")
    credentials: Mapped[str] = mapped_column(default="")
    created_at: Mapped[int] = mapped_column(default=now)


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    merchant_id: Mapped[str] = mapped_column(ForeignKey("merchants.id"))
    email: Mapped[str] = mapped_column(String(254), unique=True)
    password_hash: Mapped[str]
    role: Mapped[str] = mapped_column(default="owner")


class Product(Base):
    __tablename__ = "products"
    __table_args__ = (UniqueConstraint("merchant_id", "sku"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    merchant_id: Mapped[str] = mapped_column(ForeignKey("merchants.id"), index=True)
    sku: Mapped[str] = mapped_column(String(100))
    name: Mapped[str]
    category: Mapped[str]
    price: Mapped[int] = mapped_column(Integer)
    cost: Mapped[int | None]
    stock: Mapped[int]
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    embedding: Mapped[list] = mapped_column(JSON, default=list)
    search_vector: Mapped[list | None] = mapped_column(Vector().with_variant(JSON, "sqlite"), nullable=True)
    updated_at: Mapped[int] = mapped_column(default=now)


class Record(Base):
    """Versioned domain documents; financial amounts are integer paise.

    Records are scoped by workspace and kind. Merchant row locking serializes
    financial decisions, including reservation changes across multiple products.
    """

    __tablename__ = "records"
    __table_args__ = (UniqueConstraint("merchant_id", "kind", "key"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    merchant_id: Mapped[str] = mapped_column(ForeignKey("merchants.id"), index=True)
    kind: Mapped[str] = mapped_column(String(40), index=True)
    key: Mapped[str | None] = mapped_column(String(200), nullable=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[int] = mapped_column(default=now, index=True)


class Audit(Base):
    __tablename__ = "audit_events"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    merchant_id: Mapped[str] = mapped_column(ForeignKey("merchants.id"), index=True)
    event: Mapped[str]
    actor: Mapped[str]
    reference: Mapped[str] = mapped_column(default="", index=True)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[int] = mapped_column(default=now, index=True)


def make_engine(url):
    kwargs = {"connect_args": {"check_same_thread": False, "timeout": 30}} if url.startswith("sqlite") else {}
    engine = create_engine(url, **kwargs)
    if url.startswith("sqlite"):

        @event.listens_for(engine, "connect")
        def setup_sqlite(connection, _):
            connection.execute("PRAGMA foreign_keys=ON")
            connection.execute("PRAGMA journal_mode=WAL")

    return engine


engine = make_engine(get_settings().database_url)
SessionLocal = sessionmaker(engine, expire_on_commit=False)


def audit(db, merchant, event_name, actor="system", reference="", **data):
    row = Audit(merchant_id=merchant, event=event_name, actor=actor, reference=reference, data=data)
    db.add(row)
    return row
