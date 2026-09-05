from types import SimpleNamespace

import pytest

from backend.app.policies import evaluate
from backend.app.schemas import Policy, RuleOverride


def product(**changes):
    return SimpleNamespace(
        id="p1",
        sku="S1",
        category="headphones",
        name="Headphones",
        price=10000,
        cost=changes.get("cost", 6000),
        data={"delivery_days": 3, "compatibility": []},
    )


@pytest.mark.parametrize(
    "amount,decision",
    [
        (10000, "ALLOW"),
        (9500, "ALLOW"),
        (9499, "REQUIRE_APPROVAL"),
        (9000, "REQUIRE_APPROVAL"),
        (8999, "DENY"),
    ],
)
def test_discount_boundaries(amount, decision):
    result = evaluate(Policy(), [product()], [{"quantity": 1}], amount, {"p1": 5})
    assert result["decision"] == decision


def test_margin_is_a_gross_margin_floor_and_rounds_up():
    result = evaluate(Policy(), [product(cost=7601)], [{"quantity": 1}], 9501, {"p1": 5})
    assert result["floor"] == 9502
    assert result["decision"] == "DENY"


def test_sku_product_category_precedence():
    policy = Policy(
        category_overrides={"headphones": RuleOverride(absolute_discount_max=15)},
        product_overrides={"p1": RuleOverride(absolute_discount_max=12)},
        sku_overrides={"S1": RuleOverride(absolute_discount_max=8)},
    )
    result = evaluate(policy, [product()], [{"quantity": 1}], 9100, {"p1": 5})
    assert result["floor"] == 9200 and result["decision"] == "DENY"


def test_expired_override_cannot_expand_authority():
    result = evaluate(
        Policy(), [product()], [{"quantity": 1}], 8000, {"p1": 5}, override={"total": 8000, "expires_at": 1}
    )
    assert result["decision"] == "DENY"


def test_override_never_bypasses_margin_or_inventory():
    from backend.app.db import now

    override = {"total": 7000, "expires_at": now() + 100}
    assert evaluate(Policy(), [product()], [{"quantity": 1}], 7000, {"p1": 5}, override)["decision"] == "DENY"
    override["total"] = 8000
    assert evaluate(Policy(), [product()], [{"quantity": 1}], 8000, {"p1": 0}, override)["decision"] == "DENY"


def test_missing_cost_disables_automatic_financial_action():
    result = evaluate(Policy(), [product(cost=None)], [{"quantity": 1}], 10000, {"p1": 5})
    assert result["decision"] == "DENY" and result["hard_denial"]


def test_high_value_order_requires_approval_at_boundary():
    policy = Policy(auto_transaction_limit=10000, human_approval_threshold=10000)
    assert (
        evaluate(policy, [product()], [{"quantity": 1}], 10000, {"p1": 5})["decision"] == "REQUIRE_APPROVAL"
    )


def test_invalid_policy_cannot_be_saved():
    with pytest.raises(ValueError):
        Policy(auto_discount_max=20, absolute_discount_max=10)
    with pytest.raises(ValueError):
        Policy(rescue_discount_max=6)
