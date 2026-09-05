import hashlib
import hmac
import json
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select, text
from sqlalchemy.orm import sessionmaker

from backend.app import auth, payments
from backend.app.db import Base, Product, Record, User, make_engine, now
from backend.app.main import app, rate_windows


@pytest.fixture
def system(tmp_path, monkeypatch):
    engine = make_engine(f"sqlite:///{tmp_path}/test.db")
    Base.metadata.create_all(engine)
    factory = sessionmaker(engine, expire_on_commit=False)

    def get_db(request: __import__("fastapi").Request):
        with factory() as db:
            if request.method not in ("GET", "HEAD", "OPTIONS"):
                db.execute(text("BEGIN IMMEDIATE"))
            try:
                yield db
                db.commit()
            except Exception:
                db.rollback()
                raise

    app.dependency_overrides[auth.get_db] = get_db
    rate_windows.clear()
    monkeypatch.setattr("backend.app.main.enrichment_job", lambda *args: None)
    monkeypatch.setattr(
        payments,
        "credentials",
        lambda *args: {
            "key_id": "rzp_test_dummy",
            "key_secret": "test-secret-only",
            "webhook_secret": "webhook-secret-only",
        },
    )
    remote = {"orders": [], "payments": [], "fail_create": False}

    async def create_order(self, amount, receipt):
        if remote["fail_create"]:
            import httpx

            raise httpx.ReadTimeout("ambiguous")
        order = {
            "id": "order_" + str(len(remote["orders"]) + 1),
            "amount": amount,
            "currency": "INR",
            "receipt": receipt,
        }
        remote["orders"].append(order)
        return order

    async def order_payments(self, identifier):
        return [p for p in remote["payments"] if p["order_id"] == identifier]

    async def payment(self, identifier):
        return next(p for p in remote["payments"] if p["id"] == identifier)

    monkeypatch.setattr(payments.Razorpay, "create_order", create_order)
    monkeypatch.setattr(payments.Razorpay, "order_payments", order_payments)
    monkeypatch.setattr(payments.Razorpay, "payment", payment)
    client = TestClient(app)
    response = client.post(
        "/api/v1/auth/register",
        json={"email": "owner@example.com", "password": "secure-password", "merchant_name": "Test shop"},
    )
    assert response.status_code == 201, response.text
    session = response.json()
    client.headers["Authorization"] = "Bearer " + session["access_token"]
    rows = [
        {
            "sku": "H1",
            "name": "Wireless Office Headphones",
            "category": "headphones",
            "price": 7500,
            "cost": 4000,
            "stock": 40,
            "description": "Lightweight gaming office wireless battery",
            "attributes": {"wireless": True},
            "delivery_days": 3,
            "return_days": 7,
            "warranty": "1 year",
        },
        {
            "sku": "H2",
            "name": "Expensive headphones",
            "category": "headphones",
            "price": 9500,
            "cost": 6000,
            "stock": 10,
            "attributes": {"wireless": True},
            "delivery_days": 3,
        },
        {
            "sku": "H3",
            "name": "Wired headphones",
            "category": "headphones",
            "price": 3000,
            "cost": 1000,
            "stock": 10,
            "attributes": {"wireless": False},
            "delivery_days": 3,
        },
        {
            "sku": "A1",
            "name": "Bluetooth adapter",
            "category": "adapters",
            "price": 400,
            "cost": 150,
            "stock": 40,
            "compatibility": ["H1"],
            "delivery_days": 3,
        },
        {
            "sku": "M1",
            "name": "Office monitor",
            "category": "monitors",
            "price": 12500,
            "cost": 7800,
            "stock": 40,
            "delivery_days": 3,
        },
    ]
    result = client.post(
        "/api/v1/catalog/import",
        files={"file": ("products.json", json.dumps(rows).encode(), "application/json")},
    )
    assert result.status_code == 200, result.text
    yield client, factory, remote, session
    app.dependency_overrides.clear()
    engine.dispose()


def prepare(client, offer=720000, quantity=1, category="headphones"):
    result = client.post(
        "/api/v1/commerce/discover", json={"intent": {"category": category, "quantity": quantity}}
    )
    assert result.status_code == 200, result.text
    data = result.json()
    candidate = next(
        p for p in data["candidates"] if p["sku"] == ("H1" if category == "headphones" else "M1")
    )
    result = client.post(
        "/api/v1/commerce/negotiate",
        json={
            "session_id": data["session_id"],
            "lines": [{"product_id": candidate["id"], "quantity": quantity}],
            "offered_total": offer,
        },
    )
    assert result.status_code == 200, result.text
    return result.json()


def quoted(client):
    negotiation = prepare(client)
    result = client.post("/api/v1/commerce/quote", json={"negotiation_id": negotiation["id"]})
    assert result.status_code == 200, result.text
    return result.json()


def checkout(client, quote):
    result = client.post(
        "/api/v1/commerce/checkout",
        json={"quote_id": quote["id"], "idempotency_key": "attempt-" + quote["id"]},
    )
    assert result.status_code == 200, result.text
    return result.json()


def test_discovery_hard_constraints_and_memory(system):
    client, *_ = system
    result = client.post(
        "/api/v1/commerce/discover",
        json={"message": "Wireless headphones under ₹8,000 for gaming and office meetings"},
    )
    assert result.status_code == 200, result.text
    data = result.json()
    assert [p["sku"] for p in data["candidates"]] == ["H1"]
    follow = client.post(
        "/api/v1/commerce/discover",
        json={"session_id": data["session_id"], "message": "Battery life matters too"},
    ).json()
    assert follow["intent"]["budget"] == 800000
    assert follow["intent"]["attributes"]["wireless"] is True
    assert all(p["price"] <= 800000 for p in follow["candidates"])
    assert any(o["type"] == "bundle" for o in data["offers"])


def test_import_errors_duplicates_and_workspace_isolation(system):
    client, _, _, session = system
    result = client.post(
        "/api/v1/catalog/import",
        files={
            "file": (
                "bad.csv",
                b"sku,name,category,price,stock\nH1,Duplicate,headphones,30,1\nBAD,Bad,headphones,-5,2\n",
                "text/csv",
            )
        },
    ).json()
    assert result["duplicates"] == 1 and result["rejected"] == 1
    second = client.post(
        "/api/v1/auth/register",
        json={"email": "other@example.com", "password": "another-password", "merchant_name": "Other shop"},
    ).json()
    client.headers["Authorization"] = "Bearer " + second["access_token"]
    assert client.get("/api/v1/catalog/products").json()["products"] == []
    client.headers["Authorization"] = "Bearer " + session["access_token"]
    assert len(client.get("/api/v1/catalog/products").json()["products"]) == 5


def test_policy_final_floor_and_approval_gate(system):
    client, *_ = system
    negotiation = prepare(client, offer=100000)
    assert negotiation["total"] == 675000
    assert negotiation["final_offer"] is True
    assert negotiation["status"] == "AWAITING_APPROVAL"
    assert (
        client.post("/api/v1/commerce/quote", json={"negotiation_id": negotiation["id"]}).status_code == 409
    )
    approval = client.get("/api/v1/approvals").json()["approvals"][0]
    result = client.post(
        "/api/v1/approvals/" + approval["id"] + "/decision",
        json={"decision": "approve", "reason": "Within our approved margin"},
    )
    assert result.status_code == 200, result.text
    assert (
        client.post("/api/v1/commerce/quote", json={"negotiation_id": negotiation["id"]}).status_code == 200
    )


def test_bulk_quote_override_does_not_change_global_policy(system):
    client, *_ = system
    before = client.get("/api/v1/policies").json()
    negotiation = prepare(client, offer=33000000, quantity=30, category="monitors")
    assert negotiation["bulk"] and negotiation["status"] == "AWAITING_APPROVAL"
    result = client.post(
        "/api/v1/approvals/" + negotiation["approval_id"] + "/decision",
        json={"decision": "modify", "total": 33300000, "reason": "Approve strategic office order"},
    )
    assert result.status_code == 200, result.text
    assert client.get("/api/v1/policies").json() == before
    assert (
        client.post("/api/v1/commerce/quote", json={"negotiation_id": negotiation["id"]}).status_code == 200
    )


def test_duplicate_checkout_one_provider_order(system):
    client, _, remote, _ = system
    quote = quoted(client)
    first = checkout(client, quote)
    second = checkout(client, quote)
    assert first["id"] == second["id"]
    other = client.post(
        "/api/v1/commerce/checkout", json={"quote_id": quote["id"], "idempotency_key": "different-key"}
    ).json()
    assert other["id"] == first["id"]
    assert len(remote["orders"]) == 1


def test_lost_webhook_reconciliation_and_attribution(system):
    client, factory, remote, _ = system
    quote = quoted(client)
    order = checkout(client, quote)
    remote["payments"].append(
        {
            "id": "pay_capture",
            "order_id": order["razorpay_order_id"],
            "status": "captured",
            "amount": order["amount"],
            "currency": "INR",
        }
    )
    reconciled = client.post("/api/v1/transactions/" + order["id"] + "/reconcile").json()
    assert reconciled["state"] == "ORDER_CONFIRMED"
    client.post("/api/v1/transactions/" + order["id"] + "/reconcile")
    with factory() as db:
        assert db.scalar(select(Product).where(Product.sku == "H1")).stock == 39
    metrics = client.get("/api/v1/analytics/revenue").json()
    assert metrics["revenue"] == 720000 and metrics["attribution"]["incremental"] == -30000
    assert metrics["orders"] == 1


def test_invalid_valid_duplicate_and_out_of_order_webhooks(system):
    client, _, _, session = system
    order = checkout(client, quoted(client))
    payment = {
        "id": "pay_webhook",
        "order_id": order["razorpay_order_id"],
        "status": "captured",
        "amount": order["amount"],
        "currency": "INR",
    }
    payload = json.dumps({"event": "payment.captured", "payload": {"payment": {"entity": payment}}}).encode()
    path = "/api/v1/webhooks/razorpay/" + session["merchant"]["id"]
    assert client.post(path, content=payload, headers={"x-razorpay-signature": "invalid"}).status_code == 400
    headers = {
        "x-razorpay-signature": hmac.new(b"webhook-secret-only", payload, hashlib.sha256).hexdigest(),
        "x-razorpay-event-id": "event-1",
    }
    assert client.post(path, content=payload, headers=headers).json()["status"] == "processed"
    assert client.post(path, content=payload, headers=headers).json()["status"] == "duplicate"
    failed = json.dumps(
        {"event": "payment.failed", "payload": {"payment": {"entity": {**payment, "status": "failed"}}}}
    ).encode()
    assert (
        client.post(
            path,
            content=failed,
            headers={
                "x-razorpay-signature": hmac.new(b"webhook-secret-only", failed, hashlib.sha256).hexdigest()
            },
        ).status_code
        == 200
    )
    assert client.get("/api/v1/orders/" + order["id"]).json()["state"] == "ORDER_CONFIRMED"


def test_inventory_unavailable_and_expired_quotes_block_payment(system):
    client, factory, remote, _ = system
    quote = quoted(client)
    with factory() as db:
        product = db.scalar(select(Product).where(Product.sku == "H1"))
        product.stock = 0
        db.commit()
    result = client.post(
        "/api/v1/commerce/checkout", json={"quote_id": quote["id"], "idempotency_key": "unavailable-test"}
    )
    assert result.status_code == 409
    assert remote["orders"] == []
    with factory() as db:
        row = db.get(Record, quote["id"])
        row.data = {**row.data, "expires_at": now() - 1}
        db.commit()
    assert (
        client.post(
            "/api/v1/commerce/checkout", json={"quote_id": quote["id"], "idempotency_key": "expired-test"}
        ).status_code
        == 409
    )


def test_payment_failure_and_controlled_retry(system):
    client, _, remote, _ = system
    order = checkout(client, quoted(client))
    remote["payments"].append(
        {
            "id": "pay_fail",
            "order_id": order["razorpay_order_id"],
            "status": "failed",
            "amount": order["amount"],
            "currency": "INR",
        }
    )
    assert (
        client.post("/api/v1/transactions/" + order["id"] + "/reconcile").json()["state"] == "PAYMENT_FAILED"
    )
    retry = client.post("/api/v1/transactions/" + order["id"] + "/retry").json()
    assert retry["state"] == "PAYMENT_PENDING"
    assert len(remote["orders"]) == 1


def test_uncertain_provider_create_is_never_reissued(system):
    client, _, remote, _ = system
    remote["fail_create"] = True
    quote = quoted(client)
    order = checkout(client, quote)
    assert order["state"] == "RECONCILIATION_REQUIRED"
    remote["fail_create"] = False
    again = checkout(client, quote)
    assert again["id"] == order["id"] and len(remote["orders"]) == 0


def test_client_signature_alone_cannot_confirm_payment(system):
    client, _, remote, _ = system
    order = checkout(client, quoted(client))
    remote["payments"].append(
        {
            "id": "pay_authorized",
            "order_id": order["razorpay_order_id"],
            "status": "authorized",
            "amount": order["amount"],
            "currency": "INR",
        }
    )
    signature = hmac.new(
        b"test-secret-only", (order["razorpay_order_id"] + "|pay_authorized").encode(), hashlib.sha256
    ).hexdigest()
    assert (
        client.post(
            "/api/v1/payments/verify",
            json={
                "order_id": order["id"],
                "razorpay_payment_id": "pay_authorized",
                "razorpay_signature": signature,
            },
        ).status_code
        == 409
    )
    assert client.get("/api/v1/orders/" + order["id"]).json()["state"] == "PAYMENT_PENDING"


def test_viewer_cannot_mutate(system):
    client, factory, _, session = system
    with factory() as db:
        db.get(User, session["user"]["id"]).role = "viewer"
        db.commit()
    assert client.get("/api/v1/catalog/products").status_code == 200
    assert client.put("/api/v1/policies", json={}).status_code == 403


def test_concurrent_reservation_cannot_oversell(system):
    client, factory, _, session = system
    with factory() as db:
        p = db.scalar(select(Product).where(Product.sku == "H1"))
        p.stock = 1
        db.commit()
    a, b = prepare(client), prepare(client)

    def reserve(negotiation):
        return client.post("/api/v1/commerce/quote", json={"negotiation_id": negotiation["id"]}).status_code

    with ThreadPoolExecutor(max_workers=2) as pool:
        statuses = list(pool.map(reserve, [a, b]))
    assert sorted(statuses) == [200, 409]


def test_missing_delivery_metadata_degrades_without_crashing(system):
    client, factory, _, _ = system
    with factory() as db:
        product = db.scalar(select(Product).where(Product.sku == "H1"))
        product.data = {**product.data, "delivery_days": None}
        db.commit()
    response = client.post("/api/v1/commerce/discover", json={"intent": {"category": "headphones"}})
    assert response.status_code == 200
    data = response.json()
    assert any(p["sku"] == "H1" for p in data["candidates"])
    h1 = next(p["id"] for p in data["candidates"] if p["sku"] == "H1")
    assert all(not any(line["product_id"] == h1 for line in o["lines"]) for o in data["offers"])


def test_round_limit_and_rescue_boundary(system):
    client, *_ = system
    n = prepare(client)
    body = {
        "session_id": n["session_id"],
        "negotiation_id": n["id"],
        "lines": n["lines"],
        "offered_total": 720000,
        "abandonment_probability": 0.8,
    }
    for _ in range(2):
        response = client.post("/api/v1/commerce/negotiate", json=body)
        assert response.status_code == 200
        assert response.json()["economics"]["discount_percent"] <= 5
    assert response.json()["final_offer"]
    assert client.post("/api/v1/commerce/negotiate", json=body).status_code == 409


def test_payment_mismatch_and_illegal_transition_rejected(system):
    client, _, remote, _ = system
    order = checkout(client, quoted(client))
    remote["payments"].append(
        {
            "id": "pay_wrong",
            "order_id": order["razorpay_order_id"],
            "status": "captured",
            "amount": 1,
            "currency": "INR",
        }
    )
    assert client.post("/api/v1/transactions/" + order["id"] + "/reconcile").status_code == 409
    assert client.get("/api/v1/orders/" + order["id"]).json()["state"] == "PAYMENT_PENDING"


def test_quote_override_expiry_and_duplicate_decisions(system):
    client, factory, _, _ = system
    n = prepare(client, offer=675000)
    path = "/api/v1/approvals/" + n["approval_id"] + "/decision"
    body = {"decision": "approve", "reason": "Test scoped approval"}
    assert client.post(path, json=body).status_code == 200
    assert client.post(path, json=body).status_code == 409
    with factory() as db:
        row = db.get(Record, n["id"])
        row.data = {**row.data, "override": {**row.data["override"], "expires_at": now() - 1}}
        db.commit()
    assert client.post("/api/v1/commerce/quote", json={"negotiation_id": n["id"]}).status_code == 409
