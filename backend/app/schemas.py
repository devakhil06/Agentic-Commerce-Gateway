from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Register(StrictModel):
    email: str = Field(min_length=5, max_length=254, pattern=r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
    password: str = Field(min_length=10, max_length=128)
    merchant_name: str = Field(min_length=2, max_length=120)
    store_type: Literal["shopify", "woocommerce", "custom"] = "custom"


class Login(StrictModel):
    email: str = Field(max_length=254)
    password: str = Field(max_length=128)


class ProductInput(StrictModel):
    sku: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=2, max_length=200)
    category: str = Field(min_length=2, max_length=80)
    price: int = Field(gt=0, le=1_000_000_000)
    cost: int | None = Field(default=None, ge=0, le=1_000_000_000)
    stock: int = Field(ge=0, le=1_000_000)
    description: str = Field(default="", max_length=4000)
    attributes: dict = Field(default_factory=dict)
    compatibility: list[str] = Field(default_factory=list)
    delivery_days: int | None = Field(default=None, ge=1, le=90)
    return_days: int | None = Field(default=None, ge=0, le=365)
    warranty: str = ""
    image_url: str = ""
    variants: list[dict] = Field(default_factory=list)

    @field_validator("sku", "name", "category")
    @classmethod
    def trim(cls, value):
        if not value.strip():
            raise ValueError("Cannot be blank")
        return value.strip()


class RuleOverride(StrictModel):
    auto_discount_max: float | None = Field(default=None, ge=0, le=50)
    absolute_discount_max: float | None = Field(default=None, ge=0, le=80)
    minimum_margin_percent: float | None = Field(default=None, ge=0, le=95)
    min_price: int | None = Field(default=None, ge=0)


class Policy(StrictModel):
    mode: Literal["Conservative", "Balanced", "Aggressive Growth", "Custom"] = "Balanced"
    auto_discount_max: float = Field(default=5, ge=0, le=50)
    absolute_discount_max: float = Field(default=10, ge=0, le=80)
    minimum_margin_percent: float = Field(default=20, ge=0, le=95)
    auto_transaction_limit: int = Field(default=5_000_000, gt=0)
    human_approval_threshold: int = Field(default=10_000_000, gt=0)
    max_rounds: int = Field(default=3, ge=1, le=10)
    rescue_enabled: bool = True
    rescue_discount_max: float = Field(default=5, ge=0, le=5)
    abandonment_threshold: float = Field(default=0.75, ge=0, le=1)
    minimum_available: int = Field(default=0, ge=0)
    reservation_ttl_minutes: int = Field(default=15, ge=1, le=60)
    quote_ttl_minutes: int = Field(default=15, ge=1, le=60)
    max_estimated_days: int = Field(default=7, ge=1, le=60)
    bundle_enabled: bool = True
    max_products: int = Field(default=3, ge=1, le=10)
    bulk_min_quantity: int = Field(default=20, ge=2)
    bulk_min_order_value: int = Field(default=20_000_000, gt=0)
    bulk_opportunity_threshold: float = Field(default=0.6, ge=0, le=1)
    blocked_products: list[str] = Field(default_factory=list)
    blocked_categories: list[str] = Field(default_factory=list)
    allowed_categories: list[str] = Field(default_factory=list)
    category_overrides: dict[str, RuleOverride] = Field(default_factory=dict)
    product_overrides: dict[str, RuleOverride] = Field(default_factory=dict)
    sku_overrides: dict[str, RuleOverride] = Field(default_factory=dict)

    @model_validator(mode="after")
    def valid_boundaries(self):
        if self.auto_discount_max > self.absolute_discount_max:
            raise ValueError("Automatic discount cannot exceed the absolute discount")
        return self


class Intent(StrictModel):
    category: str | None = None
    budget: int | None = Field(default=None, gt=0, description="Total cart budget in paise")
    quantity: int = Field(default=1, ge=1, le=10000)
    max_delivery_days: int | None = Field(default=None, ge=1, le=90)
    attributes: dict[str, str | bool | int | float] = Field(default_factory=dict)
    preferences: list[str] = Field(default_factory=list)


class Discover(StrictModel):
    session_id: str | None = Field(default=None, max_length=100)
    message: str = Field(default="", max_length=4000)
    intent: Intent | None = None


class Line(StrictModel):
    product_id: str
    quantity: int = Field(ge=1, le=10000)
    kind: Literal["baseline", "upsell", "cross_sell"] = "baseline"


class Negotiate(StrictModel):
    session_id: str
    negotiation_id: str | None = None
    lines: list[Line] = Field(min_length=1, max_length=10)
    offered_total: int = Field(gt=0, le=1_000_000_000_000)
    abandonment_probability: float = Field(default=0, ge=0, le=1)
    delivery_days: int | None = Field(default=None, ge=1, le=90)


class QuoteRequest(StrictModel):
    negotiation_id: str


class CheckoutRequest(StrictModel):
    quote_id: str
    idempotency_key: str = Field(min_length=8, max_length=120)


class ApprovalDecision(StrictModel):
    decision: Literal["approve", "reject", "modify"]
    total: int | None = Field(default=None, gt=0)
    reason: str = Field(min_length=3, max_length=500)


class VerifyPayment(StrictModel):
    order_id: str
    razorpay_payment_id: str = Field(max_length=100)
    razorpay_signature: str = Field(min_length=64, max_length=64)


class Credentials(StrictModel):
    key_id: str = Field(pattern=r"^rzp_test_[A-Za-z0-9]+$")
    key_secret: str = Field(min_length=10, max_length=200)
    webhook_secret: str = Field(min_length=16, max_length=200)
