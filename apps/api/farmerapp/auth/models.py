"""Auth entities (SPEC 8.2 ``user``; FA-001 ``otp_challenge``; SEC-020 ``refresh_token``).

Every table carries the base columns (tenant_id included) so FA-003 can attach uniform RLS
policies. ``otp_challenge`` rows are created before login, so their ``tenant_id`` is the
resolved user's tenant.
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
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class UserRole(StrEnum):
    """The ten roles from FA-002."""

    OWNER = "owner"
    DIRECTOR = "director"
    CLUSTER_HEAD = "cluster_head"
    AUDITOR = "auditor"
    STORE_MANAGER = "store_manager"
    ACCOUNTANT = "accountant"
    FIELD_OFFICER = "field_officer"
    AGRONOMIST = "agronomist"
    TENANT_ADMIN = "tenant_admin"
    FARMER = "farmer"


class UserStatus(StrEnum):
    ACTIVE = "active"
    DISABLED = "disabled"


class OtpPurpose(StrEnum):
    LOGIN = "login"
    FARMER_CONFIRM = "farmer_confirm"  # FA-016
    FARMER_REGISTER = "farmer_register"  # FA-012
    MEETING_ATTENDANCE = "meeting_attendance"  # FA-027


class OtpChannel(StrEnum):
    SMS = "sms"
    WHATSAPP = "whatsapp"


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


class User(Base, BaseColumns):
    __tablename__ = "user"
    __table_args__ = (
        UniqueConstraint("tenant_id", "phone"),
        CheckConstraint(f"role IN ({_in(UserRole)})", name="role"),
        CheckConstraint(f"status IN ({_in(UserStatus)})", name="status"),
        Index("ix_user_phone", "phone"),
    )

    phone: Mapped[str] = mapped_column(String(16), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    store_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    cluster_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    language: Mapped[str] = mapped_column(String(8), nullable=False, server_default=text("'en'"))
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'active'"), default=UserStatus.ACTIVE
    )
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)


class OtpChallenge(Base, BaseColumns):
    __tablename__ = "otp_challenge"
    __table_args__ = (
        CheckConstraint(f"purpose IN ({_in(OtpPurpose)})", name="purpose"),
        CheckConstraint(f"channel IN ({_in(OtpChannel)})", name="channel"),
        Index("ix_otp_challenge_phone_purpose_created", "phone", "purpose", "created_at"),
    )

    phone: Mapped[str] = mapped_column(String(16), nullable=False)
    purpose: Mapped[str] = mapped_column(String(32), nullable=False)
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    resend_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    window_started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    channel: Mapped[str] = mapped_column(String(16), nullable=False, default=OtpChannel.SMS)
    sms_sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    whatsapp_sent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    provider_ref: Mapped[str | None] = mapped_column(String(64), nullable=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)


class RefreshToken(Base, BaseColumns):
    __tablename__ = "refresh_token"
    __table_args__ = (
        UniqueConstraint("token_hash"),
        Index("ix_refresh_token_family_id", "family_id"),
        Index("ix_refresh_token_user_id", "user_id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="CASCADE"), nullable=False
    )
    family_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    device_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    replaced_by: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
