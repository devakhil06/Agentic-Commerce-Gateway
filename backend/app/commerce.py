from fastapi import HTTPException
from sqlalchemy import select

from .agents import explain_negotiation
from .catalog import products_for
from .db import Product, audit, now
from .policies import economics, evaluate, policy_for, policy_record
from .repository import by_key, create, get_record, pack, records


def load_lines(db, merchant, lines):
    if len({line["product_id"] for line in lines}) != len(lines):
        raise HTTPException(422, "Combine duplicate product lines before proceeding")
    result = []
    for line in lines:
        product = db.scalar(
            select(Product).where(Product.id == line["product_id"], Product.merchant_id == merchant)
        )
        if not product:
            raise HTTPException(404, "Product not found in this workspace")
        result.append(product)
    return result


def availability(db, merchant, exclude_quote=None):
    available = {p.id: p.stock for p in products_for(db, merchant)}
    active_orders = {
        r.data["quote_id"]
        for r in records(db, merchant, "order")
        if r.data["state"] in ("ORDER_CREATED", "PAYMENT_PENDING", "RECONCILIATION_REQUIRED")
    }
    for quote in records(db, merchant, "quote"):
        if quote.id == exclude_quote or quote.data["status"] in ("CONSUMED", "RELEASED"):
            continue
        if quote.data["reservation_expires_at"] <= now() and quote.id not in active_orders:
            continue
        for line in quote.data["lines"]:
            available[line["product_id"]] = available.get(line["product_id"], 0) - line["quantity"]
    return available


def validate_session(db, merchant, identifier):
    session = get_record(db, merchant, "session", identifier)
    if session.data.get("expires_at", 0) <= now():
        raise HTTPException(409, "Buyer session expired; start a new discovery")
    return session


async def negotiate(db, merchant, request):
    session = validate_session(db, merchant, request.session_id)
    lines = [line.model_dump() for line in request.lines]
    products = load_lines(db, merchant, lines)
    intent = session.data.get("intent", {})
    base = products[0]
    if intent.get("category") and base.category.lower().rstrip("s") != intent["category"].lower().rstrip("s"):
        raise HTTPException(409, "The base product violates the buyer category constraint")
    if any(
        base.data.get("attributes", {}).get(key) != value
        for key, value in intent.get("attributes", {}).items()
    ):
        raise HTTPException(409, "The base product violates a mandatory buyer attribute")
    if intent.get("max_delivery_days"):
        request.delivery_days = min(
            request.delivery_days or intent["max_delivery_days"], intent["max_delivery_days"]
        )
    policy = policy_for(db, merchant)
    prior = (
        get_record(db, merchant, "negotiation", request.negotiation_id) if request.negotiation_id else None
    )
    if prior and (
        prior.data["session_id"] != session.id
        or prior.data["status"] in ("QUOTED", "REJECTED", "AWAITING_APPROVAL")
    ):
        raise HTTPException(409, "This negotiation cannot accept another counteroffer")
    rounds = list(prior.data["rounds"]) if prior else []
    if len(rounds) >= policy.max_rounds:
        raise HTTPException(
            409, "Negotiation round limit reached. Accept the final offer or start a new request."
        )
    stock = availability(db, merchant)
    evaluation = evaluate(
        policy, products, lines, request.offered_total, stock, delivery_days=request.delivery_days
    )
    econ = economics(products, lines, request.offered_total)
    quantity_bulk = econ["quantity"] >= policy.bulk_min_quantity
    value_bulk = econ["standard_total"] >= policy.bulk_min_order_value
    opportunity = round(
        min(
            1,
            0.4 * econ["quantity"] / policy.bulk_min_quantity
            + 0.4 * econ["standard_total"] / policy.bulk_min_order_value
            + (0.2 if (econ["expected_profit"] or 0) > 0 else 0),
        ),
        2,
    )
    bulk = (quantity_bulk or value_bulk) and opportunity >= policy.bulk_opportunity_threshold
    if evaluation["hard_denial"]:
        status, total = "DENIED", request.offered_total
    else:
        special = evaluate(
            policy,
            products,
            lines,
            request.offered_total,
            stock,
            override={"total": request.offered_total, "expires_at": now() + 60},
            delivery_days=request.delivery_days,
        )
        if bulk and special["decision"] == "ALLOW":
            status, total = "AWAITING_APPROVAL", request.offered_total
        else:
            total = max(request.offered_total, evaluation["floor"])
            accepted = evaluate(policy, products, lines, total, stock, delivery_days=request.delivery_days)
            status = {"REQUIRE_APPROVAL": "AWAITING_APPROVAL", "ALLOW": "OFFER_CREATED", "DENY": "DENIED"}[
                accepted["decision"]
            ]
    rescue = bool(
        policy.rescue_enabled
        and request.abandonment_probability > policy.abandonment_threshold
        and request.offered_total < econ["standard_total"]
        and status == "OFFER_CREATED"
    )
    if rescue:
        from decimal import Decimal

        from .policies import ceil

        total = max(
            total,
            evaluation["auto_floor"],
            ceil(Decimal(econ["standard_total"]) * (1 - Decimal(str(policy.rescue_discount_max)) / 100)),
        )
    final_evaluation = evaluate(policy, products, lines, total, stock, delivery_days=request.delivery_days)
    if intent.get("budget") and total > intent["budget"]:
        status = "DENIED"
        final_evaluation = {
            **final_evaluation,
            "decision": "DENY",
            "hard_denial": True,
            "reasons": ["The final offer exceeds the buyer hard budget"],
        }
    explanation, model = await explain_negotiation(
        {
            "buyer_total": request.offered_total,
            "merchant_total": total,
            "floor": evaluation["floor"],
            "reasons": evaluation["reasons"],
            "status": status,
        }
    )
    matching_offers = [
        r
        for r in records(db, merchant, "offer")
        if r.data.get("session_id") == session.id
        and r.data.get("expires_at", 0) > now()
        and r.data["lines"] == lines
    ]
    baseline = (
        matching_offers[0].data["baseline"]
        if matching_offers
        else sum(p.price * line["quantity"] for p, line in zip(products, lines))
    )
    # Attribution labels must originate from a server-issued growth offer.
    if not matching_offers:
        lines = [{**line, "kind": "baseline"} for line in lines]
    rounds.append(
        {
            "round": len(rounds) + 1,
            "buyer_offer": request.offered_total,
            "merchant_offer": total,
            "reason": explanation,
            "decision": evaluation["decision"],
            "at": now(),
            "model": model,
            "rescue": rescue,
            "abandonment_probability": request.abandonment_probability,
        }
    )
    data = {
        "session_id": session.id,
        "lines": lines,
        "product_names": [p.name for p in products],
        "status": status,
        "rounds": rounds,
        "total": total,
        "baseline": baseline,
        "floor": evaluation["floor"],
        "final_offer": request.offered_total < evaluation["floor"] or len(rounds) >= policy.max_rounds,
        "economics": economics(products, lines, total),
        "policy": final_evaluation,
        "bulk": bulk,
        "opportunity_score": opportunity,
        "conversion_probability": 0.82 if rescue else 0.74,
        "conversion_method": "conversion-heuristic-v1",
        "delivery_days": request.delivery_days,
        "expires_at": now() + policy.quote_ttl_minutes * 60,
        "override": None,
    }
    if prior:
        prior.data = data
        row = prior
    else:
        row = create(db, merchant, "negotiation", data)
    if status == "AWAITING_APPROVAL":
        approval = create(
            db,
            merchant,
            "approval",
            {
                "negotiation_id": row.id,
                "status": "PENDING",
                "economics": data["economics"],
                "product_names": data["product_names"],
                "lines": lines,
                "reason": "Strategic bulk opportunity"
                if bulk
                else "Automatic discount or transaction authority exceeded",
                "recommended_total": max(total, evaluation["floor"]),
                "minimum_margin": policy.minimum_margin_percent,
                "inventory": {p.name: stock.get(p.id, 0) for p in products},
                "delivery_days": final_evaluation["delivery_days"],
                "conversion_probability": data["conversion_probability"],
                "expires_at": data["expires_at"],
            },
        )
        row.data = {**row.data, "approval_id": approval.id}
    audit(
        db,
        merchant,
        "negotiation.round",
        actor="merchant-negotiation-agent",
        reference=row.id,
        round=rounds[-1],
        policy=final_evaluation,
        bulk=bulk,
        status=status,
    )
    return pack(row)


def decide_approval(db, user, identifier, decision):
    approval = get_record(db, user.merchant_id, "approval", identifier)
    if approval.data["status"] != "PENDING":
        raise HTTPException(409, "This approval has already been decided")
    if approval.data["expires_at"] <= now():
        raise HTTPException(409, "Approval expired; request a fresh negotiation")
    negotiation = get_record(db, user.merchant_id, "negotiation", approval.data["negotiation_id"])
    if decision.decision == "reject":
        negotiation.data = {**negotiation.data, "status": "REJECTED"}
    else:
        total = decision.total if decision.decision == "modify" else negotiation.data["total"]
        if total is None:
            raise HTTPException(422, "Enter a custom offer total")
        override = {
            "total": total,
            "approver": user.id,
            "reason": decision.reason,
            "expires_at": min(approval.data["expires_at"], now() + 900),
            "consumed": False,
        }
        products = load_lines(db, user.merchant_id, negotiation.data["lines"])
        check = evaluate(
            policy_for(db, user.merchant_id),
            products,
            negotiation.data["lines"],
            total,
            availability(db, user.merchant_id),
            override,
            negotiation.data.get("delivery_days"),
        )
        if check["decision"] != "ALLOW":
            raise HTTPException(
                409,
                {"message": "The override cannot bypass stock, delivery or margin safety", "policy": check},
            )
        negotiation.data = {
            **negotiation.data,
            "status": "OFFER_CREATED",
            "total": total,
            "override": override,
            "policy": check,
            "economics": economics(products, negotiation.data["lines"], total),
        }
    approval.data = {
        **approval.data,
        "status": decision.decision.upper(),
        "approver": user.id,
        "reason_decided": decision.reason,
        "decided_at": now(),
        "total": decision.total,
    }
    audit(
        db,
        user.merchant_id,
        "approval.decided",
        actor=user.id,
        reference=negotiation.id,
        approval_id=approval.id,
        decision=decision.decision,
        reason=decision.reason,
    )
    return pack(approval)


def quote(db, merchant, negotiation_id):
    existing = by_key(db, merchant, "quote", negotiation_id)
    if existing:
        return pack(existing)
    negotiation = get_record(db, merchant, "negotiation", negotiation_id)
    data = negotiation.data
    if data["status"] != "OFFER_CREATED" or data["expires_at"] <= now():
        raise HTTPException(409, "Offer is unavailable, expired, or awaiting merchant approval")
    policy = policy_for(db, merchant)
    products = load_lines(db, merchant, data["lines"])
    check = evaluate(
        policy,
        products,
        data["lines"],
        data["total"],
        availability(db, merchant),
        data.get("override"),
        data.get("delivery_days"),
    )
    if check["decision"] != "ALLOW":
        raise HTTPException(409, check)
    policy_row = policy_record(db, merchant)
    expires_at = min(data["expires_at"], now() + policy.quote_ttl_minutes * 60)
    if data.get("override"):
        expires_at = min(expires_at, data["override"]["expires_at"])
    row = create(
        db,
        merchant,
        "quote",
        {
            **data,
            "status": "RESERVED",
            "negotiation_id": negotiation.id,
            "prices": {p.id: p.price for p in products},
            "expires_at": expires_at,
            "reservation_expires_at": min(expires_at, now() + policy.reservation_ttl_minutes * 60),
            "policy_version": policy_row.data["version"] if policy_row else 0,
            "delivery_days": check["delivery_days"],
        },
        key=negotiation.id,
    )
    negotiation.data = {**data, "status": "QUOTED", "quote_id": row.id}
    audit(
        db,
        merchant,
        "quote.accepted.inventory_reserved",
        reference=row.id,
        lines=data["lines"],
        total=data["total"],
        expires_at=expires_at,
        policy=check,
    )
    return pack(row)
