import csv
import io
import json
from decimal import Decimal, InvalidOperation

from pydantic import ValidationError
from sqlalchemy import select

from .db import Product, audit, now
from .repository import records
from .schemas import ProductInput


def products_for(db, merchant):
    return list(db.scalars(select(Product).where(Product.merchant_id == merchant).order_by(Product.name)))


def product_json(product, available=None):
    return {
        "id": product.id,
        "sku": product.sku,
        "name": product.name,
        "category": product.category,
        "price": product.price,
        "cost": product.cost,
        "stock": product.stock,
        "available": product.stock if available is None else available,
        "updated_at": product.updated_at,
        **product.data,
    }


def quality_issues(product):
    data = product.data
    issues = []
    for field, label in [
        ("description", "Add a useful product description"),
        ("attributes", "Add product specifications"),
        ("compatibility", "Verify accessory compatibility"),
        ("delivery_days", "Set a verified delivery estimate"),
        ("warranty", "Add warranty details"),
    ]:
        if not data.get(field):
            issues.append({"field": field, "action": label})
    if data.get("return_days") is None:
        issues.append({"field": "return_days", "action": "Set a return policy"})
    if product.cost is None:
        issues.append({"field": "cost", "action": "Add cost to enable margin-safe negotiation"})
    return issues


def import_catalog(db, merchant, content, filename, currency_unit="rupees"):
    text = content.decode("utf-8-sig")
    if filename.lower().endswith(".csv"):
        rows = list(csv.DictReader(io.StringIO(text)))
    elif filename.lower().endswith(".json"):
        parsed = json.loads(text)
        rows = parsed.get("products", []) if isinstance(parsed, dict) else parsed
    else:
        raise ValueError("Upload a CSV or JSON file")
    if not isinstance(rows, list) or not rows or len(rows) > 10000:
        raise ValueError("Provide between 1 and 10,000 product records")
    existing = {p.sku: p for p in products_for(db, merchant)}
    result = {"accepted": 0, "rejected": 0, "duplicates": 0, "warnings": 0, "errors": [], "product_ids": []}
    seen = set()
    aliases = {
        "variant sku": "sku",
        "title": "name",
        "product_name": "name",
        "product type": "category",
        "variant price": "price",
        "regular_price": "price",
        "cost_per_item": "cost",
        "variant inventory qty": "stock",
        "stock_quantity": "stock",
        "body (html)": "description",
    }
    for index, source in enumerate(rows, 2):
        try:
            if not isinstance(source, dict):
                raise ValueError("Row must be an object")
            row = {aliases.get(k.lower().strip(), k.lower().strip()): v for k, v in source.items()}
            row = {k: v for k, v in row.items() if k in ProductInput.model_fields and v not in ("", None)}
            for field in ["price", "cost"]:
                if field in row:
                    amount = Decimal(str(row[field]).replace(",", ""))
                    amount *= 100 if currency_unit == "rupees" else 1
                    if not amount.is_finite() or amount != amount.to_integral_value():
                        raise ValueError(f"{field}: use at most two decimal places in rupees")
                    row[field] = int(amount)
            for field in ["attributes", "variants", "compatibility"]:
                if isinstance(row.get(field), str):
                    row[field] = json.loads(row[field])
            item = ProductInput.model_validate(row)
            if item.sku in seen or item.sku in existing:
                result["duplicates"] += 1
                result["errors"].append(
                    {
                        "row": index,
                        "field": "sku",
                        "message": f"Duplicate SKU {item.sku}; existing product preserved",
                    }
                )
                continue
            seen.add(item.sku)
            fields = item.model_dump()
            product = Product(
                merchant_id=merchant,
                **{k: fields.pop(k) for k in ["sku", "name", "category", "price", "cost", "stock"]},
                data=fields,
            )
            db.add(product)
            db.flush()
            result["product_ids"].append(product.id)
            result["accepted"] += 1
            result["warnings"] += len(quality_issues(product))
        except (ValidationError, ValueError, TypeError, InvalidOperation) as exc:
            result["rejected"] += 1
            if isinstance(exc, ValidationError):
                result["errors"].extend(
                    {"row": index, "field": ".".join(map(str, e["loc"])), "message": e["msg"]}
                    for e in exc.errors()
                )
            else:
                result["errors"].append({"row": index, "field": "record", "message": str(exc)})
    audit(
        db,
        merchant,
        "catalog.imported",
        accepted=result["accepted"],
        rejected=result["rejected"],
        duplicates=result["duplicates"],
    )
    return result


def readiness(db, merchant, payment_ready):
    products = products_for(db, merchant)
    count = len(products)

    def ratio(check):
        return round(sum(bool(check(p)) for p in products) / count * 100) if count else 0

    metrics = [
        (
            "Catalog completeness",
            20,
            ratio(lambda p: p.cost is not None and p.data.get("attributes")),
            "catalog",
            "Add cost and specifications",
        ),
        (
            "Semantic quality",
            15,
            ratio(lambda p: bool(p.embedding)),
            "catalog",
            "Generate semantic embeddings",
        ),
        (
            "Inventory freshness",
            10,
            ratio(lambda p: now() - p.updated_at < 86400),
            "catalog",
            "Refresh product inventory",
        ),
        (
            "Price freshness",
            10,
            ratio(lambda p: now() - p.updated_at < 86400),
            "catalog",
            "Verify current prices",
        ),
        (
            "Shipping readiness",
            10,
            ratio(lambda p: p.data.get("delivery_days")),
            "catalog",
            "Add verified delivery estimates",
        ),
        (
            "Returns and warranty",
            10,
            ratio(lambda p: p.data.get("return_days") is not None and p.data.get("warranty")),
            "catalog",
            "Complete return and warranty terms",
        ),
        (
            "Payment readiness",
            10,
            100 if payment_ready else 0,
            "settings",
            "Connect Razorpay test credentials",
        ),
        (
            "Agent discoverability",
            5,
            ratio(lambda p: p.data.get("description")),
            "catalog",
            "Add searchable descriptions",
        ),
        (
            "Policy configuration",
            5,
            100 if records(db, merchant, "policy") else 0,
            "policies",
            "Save merchant guardrails",
        ),
        ("Protocol compatibility", 5, 100, "settings", "Universal API v1 available"),
    ]
    components = [
        {
            "name": name,
            "weight": weight,
            "score": score,
            "deduction": round(weight * (100 - score) / 100, 1),
            "action": action,
            "route": route,
        }
        for name, weight, score, route, action in metrics
    ]
    return {
        "score": round(sum(x["weight"] * x["score"] / 100 for x in components)),
        "components": components,
        "product_count": count,
        "method": "readiness-v1",
        "issues": [
            {"id": p.id, "name": p.name, "issues": quality_issues(p)} for p in products if quality_issues(p)
        ],
    }
