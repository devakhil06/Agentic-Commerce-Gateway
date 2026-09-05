from decimal import ROUND_CEILING, Decimal

from .db import now
from .repository import records
from .schemas import Policy


def ceil(value):
    return int(Decimal(str(value)).to_integral_value(rounding=ROUND_CEILING))


def policy_record(db, merchant):
    rows = records(db, merchant, "policy")
    return max(rows, key=lambda r: r.data["version"]) if rows else None


def policy_for(db, merchant):
    row = policy_record(db, merchant)
    return Policy.model_validate(row.data["rules"]) if row else Policy()


def effective_rules(policy, product):
    rule = policy.model_dump()
    for group, key in [
        (policy.category_overrides, product.category),
        (policy.product_overrides, product.id),
        (policy.sku_overrides, product.sku),
    ]:
        if key in group:
            rule.update(group[key].model_dump(exclude_none=True))
    rule["auto_discount_max"] = min(rule["auto_discount_max"], rule["absolute_discount_max"])
    return rule


def economics(products, lines, total):
    standard = sum(p.price * line["quantity"] for p, line in zip(products, lines))
    cost_known = all(p.cost is not None for p in products)
    cost = sum((p.cost or 0) * line["quantity"] for p, line in zip(products, lines))
    return {
        "standard_total": standard,
        "offered_total": total,
        "cost": cost if cost_known else None,
        "discount_percent": round((standard - total) * 100 / standard, 2),
        "margin_percent": round((total - cost) * 100 / total, 2) if cost_known and total else None,
        "expected_profit": total - cost if cost_known else None,
        "quantity": sum(line["quantity"] for line in lines),
    }


def evaluate(policy, products, lines, total, available, override=None, delivery_days=None):
    info = economics(products, lines, total)
    reasons = []
    floor = auto_floor = 0
    hard_denial = False
    if len(products) > policy.max_products or (len(products) > 1 and not policy.bundle_enabled):
        reasons.append("Bundle size exceeds the configured limit")
        hard_denial = True
    if len(products) > 1:
        base = products[0]
        for product in products[1:]:
            if base.sku not in product.data.get("compatibility", []) and product.sku not in base.data.get(
                "compatibility", []
            ):
                reasons.append(f"{product.name}: compatibility with {base.name} is unverified")
                hard_denial = True
    override_valid = bool(override and override.get("expires_at", 0) > now() and not override.get("consumed"))
    for product, line in zip(products, lines):
        rules = effective_rules(policy, product)
        quantity = line["quantity"]
        price = product.price * quantity
        margin_floor = ceil(
            Decimal(product.cost or 0) * quantity / (1 - Decimal(str(rules["minimum_margin_percent"])) / 100)
        )
        discount_floor = ceil(Decimal(price) * (1 - Decimal(str(rules["absolute_discount_max"])) / 100))
        floor += max(
            margin_floor, 0 if override_valid else discount_floor, rules.get("min_price", 0) * quantity
        )
        auto_floor += max(
            margin_floor,
            ceil(Decimal(price) * (1 - Decimal(str(rules["auto_discount_max"])) / 100)),
            rules.get("min_price", 0) * quantity,
        )
        if product.cost is None:
            reasons.append(f"{product.name}: cost is missing; margin cannot be verified")
            hard_denial = True
        if (
            product.id in policy.blocked_products
            or product.sku in policy.blocked_products
            or product.category in policy.blocked_categories
            or (policy.allowed_categories and product.category not in policy.allowed_categories)
        ):
            reasons.append(f"{product.name}: blocked by catalog policy")
            hard_denial = True
        if available.get(product.id, 0) - quantity < policy.minimum_available:
            reasons.append(f"{product.name}: insufficient available inventory")
            hard_denial = True
        eta = product.data.get("delivery_days")
        if not eta or eta > policy.max_estimated_days or (delivery_days and eta > delivery_days):
            reasons.append(f"{product.name}: requested delivery cannot be verified")
            hard_denial = True
    if total > info["standard_total"]:
        reasons.append("Offer cannot exceed current catalog prices")
        hard_denial = True
    if total < floor:
        reasons.append("Offer is below the effective discount or margin floor")
    permitted_override = override_valid and total == override.get("total")
    needs_approval = (
        total < auto_floor
        or total > policy.auto_transaction_limit
        or total >= policy.human_approval_threshold
    )
    decision = (
        "DENY"
        if hard_denial or total < floor
        else ("REQUIRE_APPROVAL" if needs_approval and not permitted_override else "ALLOW")
    )
    if decision == "REQUIRE_APPROVAL":
        reasons.append("Discount or order value exceeds automatic authority")
    if not reasons:
        reasons.append("Price, margin, stock and delivery satisfy merchant policy")
    return {
        **info,
        "decision": decision,
        "reasons": reasons,
        "floor": floor,
        "auto_floor": auto_floor,
        "hard_denial": hard_denial,
        "override_valid": permitted_override,
        "delivery_days": max((p.data.get("delivery_days") or 0 for p in products), default=0),
    }
