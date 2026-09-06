import asyncio
import secrets
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    File,
    HTTPException,
    Query,
    Request,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from . import agents, analytics, catalog, commerce, payments, policies, schemas
from .auth import current_user, encrypt, get_db, local_secret, operator, owner, passwords, token
from .config import get_settings
from .db import Audit, Merchant, Product, SessionLocal, User, audit, engine, now
from .integrity import initialize_database
from .jobs import dispatch_job
from .repository import create, get_record, pack, records
from .seed import seed_catalog


@asynccontextmanager
async def lifespan(app):
    local_secret("secret_key")
    local_secret("encryption_key")
    if get_settings().environment == "development":
        initialize_database(engine)
    yield


app = FastAPI(
    title="Agentic Commerce Gateway",
    version="1.0.0",
    lifespan=lifespan,
    description="Merchant-controlled AI commerce. All amounts are integer INR paise. Bearer authentication is required for workspace and commerce endpoints.",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().allowed_origins.split(","),
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)
rate_windows = defaultdict(deque)


@app.get("/")
def root():
    """Provide a useful deployment landing response when no static web bundle is mounted."""
    web_index = Path(__file__).resolve().parents[2] / "frontend" / "build" / "web" / "index.html"
    if web_index.exists():
        return FileResponse(web_index)
    return {
        "name": "Agentic Commerce Gateway",
        "status": "ok",
        "message": "The ACG API is running. Open /docs for the API explorer.",
        "health": "/api/health",
        "capabilities": "/api/v1/commerce/capabilities",
    }


@app.middleware("http")
async def security_headers(request, call_next):
    if request.url.path.startswith("/api/") and not request.url.path.startswith("/api/v1/webhooks/"):
        key = (request.client.host if request.client else "local") + (
            ":auth" if "/auth/" in request.url.path else ":api"
        )
        limit = 20 if "/auth/" in request.url.path else 240
        window = rate_windows[key]
        while window and window[0] < now() - 60:
            window.popleft()
        if len(window) >= limit:
            return JSONResponse(
                {"detail": "Too many requests. Try again shortly."},
                status_code=429,
                headers={"Retry-After": "60"},
            )
        window.append(now())
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["X-Frame-Options"] = "DENY"
    if request.url.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store"
    return response


@app.exception_handler(httpx.HTTPError)
async def provider_error(request, exc):
    return JSONResponse(
        {
            "detail": "Provider is temporarily unavailable. Existing order state is preserved; retry status verification."
        },
        status_code=502,
    )


@app.exception_handler(IntegrityError)
async def duplicate_error(request, exc):
    return JSONResponse(
        {"detail": "A conflicting record already exists. Refresh and retry."}, status_code=409
    )


@app.get("/api/health")
def health():
    return {"status": "ok", "version": "1.0.0", "environment": get_settings().environment}


def auth_response(db, user):
    return {
        "access_token": token(user),
        "token_type": "bearer",
        "user": {"id": user.id, "email": user.email, "role": user.role},
        "merchant": {"id": user.merchant_id, "name": db.get(Merchant, user.merchant_id).name},
    }


@app.post("/api/v1/auth/register", status_code=201)
def register(body: schemas.Register, db=Depends(get_db, scope="function")):
    if db.scalar(select(User).where(User.email == body.email.lower())):
        raise HTTPException(409, "An account with this email already exists")
    merchant = Merchant(name=body.merchant_name, store_type=body.store_type)
    db.add(merchant)
    db.flush()
    user = User(
        merchant_id=merchant.id,
        email=body.email.lower(),
        password_hash=passwords.hash(body.password),
        role="owner",
    )
    db.add(user)
    db.flush()
    create(
        db,
        merchant.id,
        "policy",
        {"version": 1, "rules": schemas.Policy().model_dump(), "effective_at": now()},
    )
    audit(db, merchant.id, "workspace.created", actor=user.id)
    return auth_response(db, user)


@app.post("/api/v1/auth/login")
def login(body: schemas.Login, db=Depends(get_db, scope="function")):
    user = db.scalar(select(User).where(User.email == body.email.lower()))
    if not user or not passwords.verify(body.password, user.password_hash):
        raise HTTPException(401, "Email or password is incorrect")
    return auth_response(db, user)


@app.post("/api/v1/auth/demo")
async def demo(db=Depends(get_db, scope="function")):
    if get_settings().environment != "development":
        raise HTTPException(404, "Demo workspace creation is disabled")
    response = register(
        schemas.Register(
            email=f"demo-{secrets.token_hex(8)}@example.test",
            password=secrets.token_urlsafe(24),
            merchant_name="Circuit & Co.",
        ),
        db,
    )
    await seed_catalog(db, response["merchant"]["id"])
    return response


@app.get("/api/v1/me")
def me(user=Depends(current_user), db=Depends(get_db, scope="function")):
    merchant = db.get(Merchant, user.merchant_id)
    return {
        "user": {"id": user.id, "email": user.email, "role": user.role},
        "merchant": {"id": merchant.id, "name": merchant.name, "store_type": merchant.store_type},
    }


@app.get("/api/v1/integrations")
def integrations(user=Depends(current_user), db=Depends(get_db, scope="function")):
    keys = payments.credentials(db, user.merchant_id)
    settings = get_settings()
    return {
        "nvidia": {"configured": bool(settings.nvidia_api_key), "model": settings.nvidia_model},
        "razorpay": {
            "configured": bool(keys.get("key_id") and keys.get("key_secret")),
            "test_mode": True,
            "masked_key": keys.get("key_id", "")[:9] + "••••" if keys.get("key_id") else None,
            "webhook_path": f"/api/v1/webhooks/razorpay/{user.merchant_id}",
        },
        "database": "PostgreSQL" if engine.dialect.name == "postgresql" else "SQLite local development",
        "redis": bool(settings.redis_url),
        "protocols": {
            "universal": "active",
            "ACP": "extension point",
            "AP2": "extension point",
            "MCP": "extension point",
            "x402": "extension point",
        },
    }


@app.put("/api/v1/integrations/razorpay")
def connect_razorpay(body: schemas.Credentials, user=Depends(owner), db=Depends(get_db, scope="function")):
    db.get(Merchant, user.merchant_id).credentials = encrypt(body.model_dump())
    audit(db, user.merchant_id, "integration.razorpay_configured", actor=user.id)
    return {"configured": True, "test_mode": True}


@app.get("/api/v1/catalog/products")
def products(search: str = "", category: str = "", user=Depends(current_user), db=Depends(get_db, scope="function")):
    stock = commerce.availability(db, user.merchant_id)
    rows = [
        p
        for p in catalog.products_for(db, user.merchant_id)
        if (not search or search.lower() in (p.name + " " + p.sku).lower())
        and (not category or p.category == category)
    ]
    return {
        "products": [
            {**catalog.product_json(p, stock.get(p.id)), "issues": catalog.quality_issues(p)} for p in rows
        ]
    }


@app.put("/api/v1/catalog/products/{identifier}")
def update_product(identifier: str, body: schemas.ProductInput, user=Depends(operator), db=Depends(get_db, scope="function")):
    product = db.scalar(
        select(Product).where(Product.id == identifier, Product.merchant_id == user.merchant_id)
    )
    if not product:
        raise HTTPException(404, "Product not found")
    reserved = product.stock - commerce.availability(db, user.merchant_id).get(product.id, 0)
    if body.stock < reserved:
        raise HTTPException(409, "Stock cannot fall below active reservations")
    fields = body.model_dump()
    for field in ["sku", "name", "category", "price", "cost", "stock"]:
        setattr(product, field, fields.pop(field))
    product.data = fields
    product.embedding = []
    product.search_vector = None
    product.updated_at = now()
    audit(db, user.merchant_id, "catalog.product_updated", actor=user.id, reference=product.id)
    return catalog.product_json(product)


def enrichment_job(job_id):
    try:
        dispatch_job(job_id)
    except Exception:
        # The durable QUEUED record remains recoverable if Redis is unavailable.
        pass


@app.post("/api/v1/catalog/import")
async def import_products(
    background: BackgroundTasks,
    file: UploadFile = File(...),
    currency_unit: str = Query("rupees", pattern="^(rupees|paise)$"),
    user=Depends(operator),
    db=Depends(get_db, scope="function"),
):
    content = await file.read(5 * 1024 * 1024 + 1)
    if len(content) > 5 * 1024 * 1024:
        raise HTTPException(413, "Catalog uploads are limited to 5 MB")
    try:
        result = catalog.import_catalog(db, user.merchant_id, content, file.filename or "", currency_unit)
    except (ValueError, UnicodeError) as exc:
        raise HTTPException(422, str(exc)) from None
    job = create(db, user.merchant_id, "job", {"status": "QUEUED", "product_ids": result["product_ids"]})
    db.commit()
    background.add_task(enrichment_job, job.id)
    return {**result, "enrichment": "queued", "job_id": job.id}


@app.post("/api/v1/catalog/seed")
async def seed(user=Depends(operator), db=Depends(get_db, scope="function")):
    return await seed_catalog(db, user.merchant_id)


@app.post("/api/v1/catalog/enrich")
async def enrich(background: BackgroundTasks, user=Depends(operator), db=Depends(get_db, scope="function")):
    ids = [p.id for p in catalog.products_for(db, user.merchant_id)]
    job = create(db, user.merchant_id, "job", {"status": "QUEUED", "product_ids": ids})
    db.commit()
    background.add_task(enrichment_job, job.id)
    return {"queued": len(ids), "job_id": job.id}


@app.get("/api/v1/catalog/jobs")
def catalog_jobs(user=Depends(current_user), db=Depends(get_db, scope="function")):
    return {"jobs": [pack(r) for r in records(db, user.merchant_id, "job")]}


@app.post("/api/v1/catalog/jobs/{identifier}/retry")
def retry_job(identifier: str, background: BackgroundTasks, user=Depends(operator), db=Depends(get_db, scope="function")):
    job = get_record(db, user.merchant_id, "job", identifier)
    if job.data["status"] == "RUNNING":
        raise HTTPException(409, "This job is already running")
    job.data = {**job.data, "status": "QUEUED"}
    db.commit()
    background.add_task(enrichment_job, job.id)
    return pack(job)


@app.get("/api/v1/catalog/readiness")
def readiness(user=Depends(current_user), db=Depends(get_db, scope="function")):
    keys = payments.credentials(db, user.merchant_id)
    return catalog.readiness(db, user.merchant_id, bool(keys.get("key_id") and keys.get("key_secret")))


@app.get("/api/v1/policies")
def get_policy(user=Depends(current_user), db=Depends(get_db, scope="function")):
    row = policies.policy_record(db, user.merchant_id)
    return {
        "rules": policies.policy_for(db, user.merchant_id).model_dump(),
        "version": row.data["version"] if row else 0,
    }


@app.put("/api/v1/policies")
def save_policy(body: schemas.Policy, user=Depends(owner), db=Depends(get_db, scope="function")):
    row = policies.policy_record(db, user.merchant_id)
    saved = create(
        db,
        user.merchant_id,
        "policy",
        {"rules": body.model_dump(), "version": row.data["version"] + 1 if row else 1, "effective_at": now()},
    )
    audit(
        db,
        user.merchant_id,
        "policy.version_saved",
        actor=user.id,
        version=saved.data["version"],
        rules=body.model_dump(),
    )
    return pack(saved)


@app.get("/api/v1/commerce/capabilities")
def capabilities():
    return {
        "version": "1.0",
        "schema": "universal-commerce-v1",
        "currency": "INR",
        "amount_unit": "paise",
        "operations": ["discover", "recommend", "negotiate", "quote", "checkout", "order_status"],
        "authentication": "Bearer",
        "payment_environment": "razorpay_test",
        "financial_control": "deterministic",
        "protocol_adapters": {"ACP": False, "AP2": False, "MCP": False, "x402": False},
    }


@app.post("/api/v1/commerce/discover")
@app.post("/api/v1/commerce/recommend")
async def discover(body: schemas.Discover, user=Depends(operator), db=Depends(get_db, scope="function")):
    if not body.message.strip() and body.intent is None:
        raise HTTPException(422, "Enter a buyer request or structured intent")
    return await agents.discover(db, user.merchant_id, body, commerce.availability(db, user.merchant_id))


@app.delete("/api/v1/sessions/{identifier}")
def delete_session(identifier: str, user=Depends(operator), db=Depends(get_db, scope="function")):
    row = get_record(db, user.merchant_id, "session", identifier)
    row.data = {"history": [], "intent": {}, "expires_at": 0}
    audit(db, user.merchant_id, "session.memory_deleted", actor=user.id, reference=identifier)
    return {"deleted": True}


@app.post("/api/v1/commerce/negotiate")
async def negotiate(body: schemas.Negotiate, user=Depends(operator), db=Depends(get_db, scope="function")):
    return await commerce.negotiate(db, user.merchant_id, body)


@app.post("/api/v1/commerce/quote")
def quote(body: schemas.QuoteRequest, user=Depends(operator), db=Depends(get_db, scope="function")):
    return commerce.quote(db, user.merchant_id, body.negotiation_id)


@app.get("/api/v1/quotes/{identifier}")
def get_quote(identifier: str, user=Depends(current_user), db=Depends(get_db, scope="function")):
    return pack(get_record(db, user.merchant_id, "quote", identifier))


@app.post("/api/v1/commerce/checkout")
async def checkout(body: schemas.CheckoutRequest, user=Depends(operator), db=Depends(get_db, scope="function")):
    return await payments.checkout(db, user.merchant_id, body)


@app.post("/api/v1/payments/verify")
async def verify(body: schemas.VerifyPayment, user=Depends(operator), db=Depends(get_db, scope="function")):
    return await payments.verify(db, user.merchant_id, body)


@app.get("/api/v1/negotiations")
def negotiations(user=Depends(current_user), db=Depends(get_db, scope="function")):
    return {"negotiations": [pack(r) for r in records(db, user.merchant_id, "negotiation")]}


@app.get("/api/v1/approvals")
def approvals(user=Depends(current_user), db=Depends(get_db, scope="function")):
    return {
        "approvals": [
            {
                **pack(r),
                "status": "EXPIRED"
                if r.data["status"] == "PENDING" and r.data["expires_at"] <= now()
                else r.data["status"],
            }
            for r in records(db, user.merchant_id, "approval")
        ]
    }


@app.post("/api/v1/approvals/{identifier}/decision")
def decide(identifier: str, body: schemas.ApprovalDecision, user=Depends(operator), db=Depends(get_db, scope="function")):
    return commerce.decide_approval(db, user, identifier, body)


@app.get("/api/v1/transactions")
def transactions(user=Depends(current_user), db=Depends(get_db, scope="function")):
    return {"transactions": [pack(r) for r in records(db, user.merchant_id, "order")]}


@app.get("/api/v1/orders/{identifier}")
def order(identifier: str, user=Depends(current_user), db=Depends(get_db, scope="function")):
    return pack(get_record(db, user.merchant_id, "order", identifier))


@app.post("/api/v1/transactions/{identifier}/reconcile")
async def reconcile(identifier: str, user=Depends(operator), db=Depends(get_db, scope="function")):
    return await payments.reconcile(db, user.merchant_id, identifier)


@app.post("/api/v1/transactions/{identifier}/retry")
async def retry(identifier: str, user=Depends(operator), db=Depends(get_db, scope="function")):
    await payments.reconcile(db, user.merchant_id, identifier)
    order = get_record(db, user.merchant_id, "order", identifier)
    if order.data["state"] != "PAYMENT_FAILED":
        return payments.checkout_payload(order, payments.credentials(db, user.merchant_id).get("key_id", ""))
    quote = get_record(db, user.merchant_id, "quote", order.data["quote_id"])
    if min(quote.data["expires_at"], quote.data["reservation_expires_at"]) <= now():
        raise HTTPException(409, "Retry window expired; request a new quote")
    products = commerce.load_lines(db, user.merchant_id, quote.data["lines"])
    if any(p.price != quote.data["prices"][p.id] for p in products):
        raise HTTPException(409, "Prices changed; request a new quote")
    check = policies.evaluate(
        policies.policy_for(db, user.merchant_id),
        products,
        quote.data["lines"],
        quote.data["total"],
        commerce.availability(db, user.merchant_id, quote.id),
        quote.data.get("override"),
        quote.data.get("delivery_days"),
    )
    if check["decision"] != "ALLOW":
        raise HTTPException(409, check)
    payments.transition(db, order, "PAYMENT_PENDING", "Retry revalidated; reusing the same provider order")
    return payments.checkout_payload(order, payments.credentials(db, user.merchant_id)["key_id"])


class Recovery(schemas.StrictModel):
    razorpay_order_id: str


@app.post("/api/v1/transactions/{identifier}/recover-reference")
async def recover_reference(identifier: str, body: Recovery, user=Depends(owner), db=Depends(get_db, scope="function")):
    order = get_record(db, user.merchant_id, "order", identifier)
    if order.data.get("razorpay_order_id") or order.data["state"] not in (
        "ORDER_CREATED",
        "RECONCILIATION_REQUIRED",
    ):
        raise HTTPException(409, "This order does not need reference recovery")
    if (
        not body.razorpay_order_id.startswith("order_")
        or not body.razorpay_order_id.replace("_", "").isalnum()
    ):
        raise HTTPException(422, "Invalid provider order ID")
    provider = payments.Razorpay(payments.credentials(db, user.merchant_id))
    remote = await provider.request("GET", "/orders/" + body.razorpay_order_id)
    if (
        remote.get("receipt") != order.id
        or remote.get("amount") != order.data["amount"]
        or remote.get("currency") != "INR"
    ):
        raise HTTPException(409, "Provider order does not match receipt, amount and currency")
    order.data = {**order.data, "razorpay_order_id": remote["id"]}
    payments.transition(db, order, "PAYMENT_PENDING", "Owner recovered a verified provider reference")
    return await payments.reconcile(db, user.merchant_id, identifier)


@app.post("/api/v1/webhooks/razorpay/{merchant}")
async def webhook(merchant: str, request: Request, db=Depends(get_db, scope="function")):
    if not db.execute(select(Merchant).where(Merchant.id == merchant).with_for_update()).scalar_one_or_none():
        raise HTTPException(404, "Workspace not found")
    raw = await request.body()
    if len(raw) > 1024 * 1024:
        raise HTTPException(413, "Webhook too large")
    return await payments.webhook(
        db,
        merchant,
        raw,
        request.headers.get("x-razorpay-signature", ""),
        request.headers.get("x-razorpay-event-id", ""),
    )


@app.get("/api/v1/audit")
@app.get("/api/v1/transactions/{identifier}/timeline")
def timeline(identifier: str = "", user=Depends(current_user), db=Depends(get_db, scope="function")):
    references = {identifier}
    if identifier:
        order = get_record(db, user.merchant_id, "order", identifier)
        references.update([order.data["quote_id"], order.data["negotiation_id"]])
    query = select(Audit).where(Audit.merchant_id == user.merchant_id)
    if identifier:
        query = query.where(Audit.reference.in_(references))
    events = db.scalars(query.order_by(Audit.created_at.desc(), Audit.id).limit(500))
    return {
        "events": [
            {
                "id": r.id,
                "event": r.event,
                "actor": r.actor,
                "reference": r.reference,
                "data": r.data,
                "created_at": r.created_at,
            }
            for r in events
        ]
    }


@app.get("/api/v1/analytics/revenue")
@app.get("/api/v1/analytics/discovery")
@app.get("/api/v1/analytics/negotiations")
@app.get("/api/v1/analytics/lost-revenue")
def metrics(
    days: int = Query(30, ge=1, le=365),
    product: str | None = None,
    category: str | None = None,
    user=Depends(current_user),
    db=Depends(get_db, scope="function"),
):
    return analytics.analytics(db, user.merchant_id, days, product, category)


@app.websocket("/api/v1/events")
async def events(socket: WebSocket):
    import jwt

    await socket.accept()
    try:
        first = await asyncio.wait_for(socket.receive_json(), timeout=10)
        claims = jwt.decode(first["token"], local_secret("secret_key"), algorithms=["HS256"], audience="acg")
        with SessionLocal() as db:
            user = db.get(User, claims["sub"])
            if not user:
                await socket.close(code=1008)
                return
            merchant_id = user.merchant_id
        last = None
        while now() < claims["exp"]:
            with SessionLocal() as db:
                revision = db.scalar(select(func.count(Audit.id)).where(Audit.merchant_id == merchant_id))
            if revision != last:
                await socket.send_json({"type": "workspace.updated", "revision": revision})
                last = revision
            await asyncio.sleep(2)
        await socket.close(code=1008)
    except (WebSocketDisconnect, jwt.PyJWTError, KeyError, TimeoutError):
        return


web_build = Path(__file__).resolve().parents[2] / "frontend" / "build" / "web"
if web_build.exists():
    app.mount("/", StaticFiles(directory=web_build, html=True), name="web")
