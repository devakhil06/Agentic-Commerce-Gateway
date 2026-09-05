from collections import Counter, defaultdict

from .db import now
from .repository import get_record, pack, records


def analytics(db, merchant, days=30, product=None, category=None):
    cutoff = now() - days * 86400
    negotiations = [r for r in records(db, merchant, "negotiation") if r.created_at >= cutoff]
    searches = [r for r in records(db, merchant, "discovery") if r.created_at >= cutoff]
    orders = [r for r in records(db, merchant, "order") if r.created_at >= cutoff]
    if product or category:
        from .catalog import products_for

        allowed = {
            p.id
            for p in products_for(db, merchant)
            if (not product or p.id == product) and (not category or p.category == category)
        }
        negotiations = [
            r for r in negotiations if any(line["product_id"] in allowed for line in r.data["lines"])
        ]
        orders = [
            r
            for r in orders
            if any(
                line["product_id"] in allowed
                for line in get_record(db, merchant, "quote", r.data["quote_id"]).data["lines"]
            )
        ]
        searches = [r for r in searches if any(p["id"] in allowed for p in r.data["candidates"])]
    confirmed = [
        r for r in orders if r.data["state"] in ("ORDER_CONFIRMED", "FULFILLMENT_PENDING", "COMPLETED")
    ]
    revenue = sum(r.data["amount"] for r in confirmed)
    totals = {
        key: sum(r.data.get("attribution", {}).get(key, 0) for r in confirmed)
        for key in ["baseline", "upsell", "cross_sell", "discount", "incremental"]
    }
    daily = defaultdict(lambda: {"revenue": 0, "incremental": 0, "orders": 0})
    from datetime import datetime, timezone

    for order in confirmed:
        day = datetime.fromtimestamp(order.data["updated_at"], timezone.utc).strftime("%Y-%m-%d")
        daily[day]["revenue"] += order.data["amount"]
        daily[day]["incremental"] += order.data.get("attribution", {}).get("incremental", 0)
        daily[day]["orders"] += 1
    rejections = Counter(p["reason"] for search in searches for p in search.data["rejected"])
    rounds = [rnd for r in negotiations for rnd in r.data["rounds"]]
    discounts = sorted(r.data["economics"]["discount_percent"] for r in negotiations)
    pending = [
        r
        for r in records(db, merchant, "approval")
        if r.data["status"] == "PENDING" and r.data["expires_at"] > now()
    ]
    return {
        "revenue": revenue,
        "ai_revenue": revenue,
        "attribution": totals,
        "aov": round(revenue / len(confirmed)) if confirmed else 0,
        "orders": len(confirmed),
        "transactions": len(orders),
        "searches": len(searches),
        "negotiations": len(negotiations),
        "approvals": len(pending),
        "failures": sum(r.data["state"] in ("PAYMENT_FAILED", "RECONCILIATION_REQUIRED") for r in orders),
        "conversion": round(len(confirmed) / len(searches) * 100, 1) if searches else 0,
        "daily": [{"date": date, **value} for date, value in sorted(daily.items())],
        "rejections": dict(rejections),
        "offers": sum(len(r.data["offers"]) for r in searches),
        "average_rounds": round(len(rounds) / len(negotiations), 1) if negotiations else 0,
        "average_discount": round(sum(discounts) / len(discounts), 2) if discounts else 0,
        "median_discount": discounts[len(discounts) // 2] if discounts else 0,
        "rescue_discounts": sum(r["rescue"] for r in rounds),
        "abandoned": sum(
            r.data["expires_at"] < now() and r.data["status"] not in ("QUOTED", "REJECTED")
            for r in negotiations
        ),
        "bulk_opportunities": sum(r.data["bulk"] for r in negotiations),
        "bulk_revenue": sum(
            r.data["amount"]
            for r in confirmed
            if get_record(db, merchant, "quote", r.data["quote_id"]).data.get("bulk")
        ),
        "recent_orders": [pack(r) for r in orders[:6]],
        "days": days,
    }
