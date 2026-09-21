"""FM-013 data model (Alembic ``0043_m8_market_referral_nlq``).

``farmer.referral_code`` (added by the same migration) is the farmer's own code: a short,
unambiguous string the farmer app puts into a WhatsApp / SMS message. It is minted the first
time the farmer opens the Refer screen, so no backfill is needed.

``referral`` is one row per invitation, with the lifecycle FM-013 asks for::

    pending  -- an invite was shared (optionally to a known phone)
       |
       v
    attributed  -- the invited farmer registered with the code: referrer, invited farmer and
       |           the invited farmer's nearest store are all recorded, with the reward the
       |           tenant settings promised at that moment
       v
    rewarded  -- a store manager (or tenant admin) confirmed the credit was given

``rejected`` is the dead end for an invite the tenant withdrew. Duplicate and self-referral
prevention is structural as well as checked in the service:

* ``uq_referral_invited_farmer`` — a farmer can be *the invited one* at most once, ever;
* ``uq_referral_pending_phone`` — one live pending invite per (referrer, invited phone);
* ``ck_referral_not_self`` — a farmer may never refer themself.

No plain phone is stored: a pending invite keeps the SEC-026 ``phone_hash`` (to match the
registration) and ``phone_last4`` (so the console can show which invite it was).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns

#: Unambiguous alphabet: no O/0, I/1, S/5 — the code is read aloud and typed on a phone.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRTUVWXYZ23456789"
CODE_LENGTH = 8


class ReferralStatus(StrEnum):
    PENDING = "pending"
    ATTRIBUTED = "attributed"
    REWARDED = "rewarded"
    REJECTED = "rejected"


class ReferralSource(StrEnum):
    """How the code reached us."""

    #: The invited farmer entered / deep-linked it in the farmer app after signing in.
    FARMER_APP = "farmer_app"
    #: A field officer typed it while registering the farmer (FA-012).
    OFFICER = "officer"
    #: The referrer shared an invite before anyone registered (status ``pending``).
    INVITE = "invite"


def sql_in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


class Referral(Base, BaseColumns):
    __tablename__ = "referral"
    __table_args__ = (
        CheckConstraint(f"status IN ({sql_in(ReferralStatus)})", name="status"),
        CheckConstraint(f"source IN ({sql_in(ReferralSource)})", name="source"),
        CheckConstraint(
            "invited_farmer_id IS NULL OR invited_farmer_id <> referrer_farmer_id",
            name="not_self",
        ),
        CheckConstraint(
            "status <> 'attributed' OR "
            "(invited_farmer_id IS NOT NULL AND attributed_at IS NOT NULL)",
            name="attributed_complete",
        ),
        CheckConstraint(
            "status <> 'rewarded' OR rewarded_at IS NOT NULL", name="rewarded_complete"
        ),
        CheckConstraint("referrer_reward_paise >= 0", name="referrer_reward_paise"),
        CheckConstraint("store_reward_paise >= 0", name="store_reward_paise"),
        CheckConstraint("char_length(code) BETWEEN 4 AND 16", name="code"),
        Index(
            "uq_referral_invited_farmer",
            "tenant_id",
            "invited_farmer_id",
            unique=True,
            postgresql_where=text("invited_farmer_id IS NOT NULL AND deleted_at IS NULL"),
        ),
        Index(
            "uq_referral_pending_phone",
            "tenant_id",
            "referrer_farmer_id",
            "invited_phone_hash",
            unique=True,
            postgresql_where=text(
                "invited_phone_hash IS NOT NULL AND status = 'pending' AND deleted_at IS NULL"
            ),
        ),
        Index("ix_referral_referrer", "tenant_id", "referrer_farmer_id"),
        Index("ix_referral_store", "tenant_id", "store_id", "status"),
        Index("ix_referral_phone_hash", "tenant_id", "invited_phone_hash"),
    )

    #: The referrer's ``farmer.referral_code`` as used (kept even if the code is ever reissued).
    code: Mapped[str] = mapped_column(String(16), nullable=False)
    referrer_farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="CASCADE"), nullable=False
    )
    invited_farmer_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("farmer.id", ondelete="CASCADE"), nullable=True
    )
    #: SEC-026 searchable hash of the invited phone (never the number itself).
    invited_phone_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    invited_phone_last4: Mapped[str | None] = mapped_column(String(4), nullable=True)
    #: The invited farmer's nearest store — the store credited with the referral (FM-013).
    store_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("store.id", ondelete="SET NULL"), nullable=True
    )
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'pending'"), default=ReferralStatus.PENDING
    )
    source: Mapped[str] = mapped_column(String(16), nullable=False)
    #: Snapshot of ``tenant.settings.referral`` at attribution (the promise made that day).
    referrer_reward_paise: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0", default=0
    )
    store_reward_paise: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0", default=0
    )
    reward_note: Mapped[str | None] = mapped_column(String(200), nullable=True)
    attributed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    rewarded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    rewarded_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    note: Mapped[str | None] = mapped_column(Text, nullable=True)


__all__ = ["CODE_ALPHABET", "CODE_LENGTH", "Referral", "ReferralSource", "ReferralStatus"]
