from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, Field, validator
from enum import Enum

class SubscriptionStatus(str, Enum):
    ACTIVE = "active"
    EXPIRED = "expired"
    CANCELLED = "cancelled"
    PENDING_PAYMENT = "pending_payment"

class SubscriptionPlanBase(BaseModel):
    name: str = Field(..., max_length=50)
    description: Optional[str] = None
    price_in_cents: int = Field(..., gt=0, description="Price in the smallest currency unit (e.g., cents for KSH)")
    billing_cycle_days: int = Field(..., gt=0, description="Billing cycle length in days")
    features: List[str] = Field(default_factory=list, description="List of features included in this plan")
    is_active: bool = True

class SubscriptionPlanCreate(SubscriptionPlanBase):
    pass

class SubscriptionPlanInDB(SubscriptionPlanBase):
    id: int
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime] = None

    class Config:
        orm_mode = True

class SubscriptionBase(BaseModel):
    user_id: int
    plan_id: int
    status: SubscriptionStatus = SubscriptionStatus.PENDING_PAYMENT
    start_date: datetime
    end_date: Optional[datetime] = None
    payment_transaction_id: Optional[int] = None

class SubscriptionCreate(SubscriptionBase):
    @validator('start_date', pre=True, always=True)
    def set_start_date_now(cls, v):
        return v or datetime.utcnow()

class SubscriptionInDB(SubscriptionBase):
    id: int
    created_at: datetime
    updated_at: datetime
    cancelled_at: Optional[datetime] = None
    plan: Optional[SubscriptionPlanInDB] = None

    class Config:
        orm_mode = True

class PlanStatusResponse(BaseModel):
    has_active_plan: bool
    current_plan: Optional[SubscriptionInDB] = None
    days_remaining: Optional[int] = None
    is_trial: bool = False
