"""FM-013 wire shapes. Money is integer paise; no plain phone ever leaves the API here."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from farmerapp.auth.schemas import Phone
from farmerapp.referrals.models import CODE_LENGTH, ReferralStatus

#: What the farmer app puts in the WhatsApp / SMS message; the app fills in the code and the
#: reward line from ``MyReferralOut`` and takes the wording from its own i18n bundle.
SHARE_LINK_TEMPLATE = "https://kisan.farmerapp.in/r/{code}"


class ReferralCode(str):
    """A referral code as typed or deep-linked (case and separators do not matter)."""


class ReferralClaimIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str = Field(min_length=4, max_length=24, description="From the invite link.")

    @field_validator("code")
    @classmethod
    def _clean(cls, value: str) -> str:
        cleaned = "".join(ch for ch in value.upper() if ch.isalnum())
        if not 4 <= len(cleaned) <= 16:
            raise ValueError("not a referral code")
        return cleaned


class ReferralInviteIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    phone: Phone | None = Field(
        default=None,
        description="Optional: the number the invite was sent to, so the referral can be "
        "matched when that farmer registers. Stored only as a SEC-026 hash.",
    )


class ReferralOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    status: ReferralStatus
    source: str
    referrer_farmer_id: uuid.UUID
    invited_farmer_id: uuid.UUID | None = None
    invited_phone_last4: str | None = Field(
        default=None, description="Last four digits only (AN-014 / SEC-026)."
    )
    store_id: uuid.UUID | None = Field(
        default=None, description="The invited farmer's nearest store, credited with the referral."
    )
    referrer_reward_paise: int
    store_reward_paise: int
    reward_note: str | None = None
    attributed_at: datetime | None = None
    rewarded_at: datetime | None = None
    created_at: datetime


class MyReferralOut(BaseModel):
    """``GET /v1/me/referral`` — the farmer app's Refer screen (F70)."""

    farmer_id: uuid.UUID
    code: str = Field(min_length=CODE_LENGTH, max_length=CODE_LENGTH)
    share_link: str = Field(description="The link the share message carries.")
    enabled: bool
    referrer_reward_paise: int
    store_reward_paise: int
    reward_note: str | None = None
    invited: int = Field(description="Invites shared but not yet registered.")
    attributed: int = Field(description="Farmers who registered with this code.")
    rewarded: int
    referrals: list[ReferralOut] = Field(default_factory=list)


class ReferralListOut(BaseModel):
    items: list[ReferralOut] = Field(default_factory=list)
    total: int


class StoreReferralsOut(BaseModel):
    store_id: uuid.UUID | None = None
    store_code: str | None = None
    store_name: str | None = None
    pending: int
    attributed: int
    rewarded: int
    total: int
    #: Rewarded referrals only — what has actually been credited.
    referrer_reward_paise: int
    store_reward_paise: int


class ReferralSummaryOut(BaseModel):
    stores: list[StoreReferralsOut] = Field(default_factory=list)
    pending: int
    attributed: int
    rewarded: int


class ReferralRewardIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    note: str | None = Field(default=None, max_length=500)


__all__ = [
    "SHARE_LINK_TEMPLATE",
    "MyReferralOut",
    "ReferralClaimIn",
    "ReferralInviteIn",
    "ReferralListOut",
    "ReferralOut",
    "ReferralRewardIn",
    "ReferralSummaryOut",
    "StoreReferralsOut",
]
