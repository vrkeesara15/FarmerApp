"""Auth entities (SPEC 8.2 ``user``; FA-001 ``otp_challenge``; SEC-020 ``refresh_token``).

Every table carries the base columns (tenant_id included) so FA-003 can attach uniform RLS
policies. ``otp_challenge`` rows are created before login, so their ``tenant_id`` is the
resolved user's tenant.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from geoalchemy2 import Geography
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns
from farmerapp.db.geo import SRID
from farmerapp.pii.fields import EncryptedField, mask_phone


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
    STEP_UP = "step_up"  # SEC-028 re-auth before admin actions


class DeviceStatus(StrEnum):
    """SEC-020 / SEC-025 device lifecycle (WC-011).

    ``pending`` — a field officer tried to log in from a second device; an admin must bind it.
    ``active`` — may log in and refresh. ``revoked`` — unbound by an admin (another device was
    bound); its sessions are gone. ``lost`` — reported lost: its sessions are gone and the app
    must wipe local data (401 ``device_wipe_required``).
    """

    PENDING = "pending"
    ACTIVE = "active"
    REVOKED = "revoked"
    LOST = "lost"


class RevokeReason(StrEnum):
    """Why a refresh token stopped working (``refresh_token.revoked_reason``)."""

    ROTATED = "rotated"
    LOGOUT = "logout"
    REUSE = "reuse"
    FORCE_LOGOUT = "force_logout"
    DEVICE_REVOKED = "device_revoked"
    DEVICE_LOST = "device_lost"
    USER_DISABLED = "user_disabled"


class OtpChannel(StrEnum):
    SMS = "sms"
    WHATSAPP = "whatsapp"


class OtpBlockScope(StrEnum):
    """SEC-021: what an ``otp_block`` row blocks (the value itself is only ever hashed)."""

    PHONE = "phone"
    IP = "ip"


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


class User(Base, BaseColumns):
    __tablename__ = "user"
    __table_args__ = (
        UniqueConstraint("tenant_id", "phone"),
        # SEC-026: the searchable hash is unique per tenant; login looks it up across tenants.
        UniqueConstraint("tenant_id", "phone_hash", name="uq_user_tenant_id_phone_hash"),
        CheckConstraint(f"role IN ({_in(UserRole)})", name="role"),
        CheckConstraint(f"status IN ({_in(UserStatus)})", name="status"),
        Index("ix_user_phone", "phone"),
        Index("ix_user_phone_hash", "phone_hash"),
    )

    # SEC-026: ``phone`` is encrypted (``phone_enc``) with a searchable ``phone_hash``; the
    # legacy plain column (``phone_plain``, SQL ``phone``) is read only until the backfill /
    # contract steps (farmerapp/pii). Query by ``farmerapp.pii.lookup.phone_match``.
    phone_plain: Mapped[str | None] = mapped_column("phone", String(16), nullable=True)
    phone_enc: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    phone_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    phone: EncryptedField[str] = EncryptedField(
        plain="phone_plain", enc="phone_enc", hash_attr="phone_hash", mask=mask_phone
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    store_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    cluster_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    language: Mapped[str] = mapped_column(String(8), nullable=False, server_default=text("'en'"))
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'active'"), default=UserStatus.ACTIVE
    )
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    # WC-011 / SEC-020: access tokens issued at or before this instant are rejected (forced
    # logout, disable). Checked on every request against the loaded row, so immediately.
    tokens_valid_after: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # VV-007: where "idle at home" is measured for an officer (NULL -> their store's location).
    home_point: Mapped[Any] = mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=True
    )


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
    #: SEC-021: the client IP the send came from, for the per-IP velocity rule. Never logged.
    request_ip: Mapped[str | None] = mapped_column(String(45), nullable=True)


class OtpBlock(Base, BaseColumns):
    """SEC-021 abuse block list: a hashed phone or IP that may not request codes for a while.

    Written by ``farmerapp.auth.otp_abuse`` when a velocity rule breaks; ``strikes`` doubles
    the window each time, which is the repeat-abuser rule. ``key_hash`` is
    ``HMAC(otp_pepper, scope || value)`` so the table holds no phone and no IP in the clear.
    """

    __tablename__ = "otp_block"
    __table_args__ = (
        UniqueConstraint("tenant_id", "key_hash", name="uq_otp_block_tenant_id_key_hash"),
        CheckConstraint(f"scope IN ({_in(OtpBlockScope)})", name="scope"),
        Index("ix_otp_block_blocked_until", "tenant_id", "blocked_until"),
    )

    scope: Mapped[str] = mapped_column(String(8), nullable=False)
    key_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    reason: Mapped[str] = mapped_column(String(32), nullable=False)
    strikes: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    blocked_until: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


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
    revoked_reason: Mapped[str | None] = mapped_column(String(32), nullable=True)


class Device(Base, BaseColumns):
    """A phone or tablet a user has signed in from (WC-011, SEC-020, SEC-025).

    Rows are written on login and refresh (``first_seen`` / ``last_seen``, platform, model,
    app version). Field officers have at most one ``active`` device: a login from another
    device is refused (409 ``device_not_bound``) and recorded as ``pending`` until an admin
    binds it. Other roles may use several active devices.
    """

    __tablename__ = "device"
    __table_args__ = (
        UniqueConstraint("tenant_id", "user_id", "device_id"),
        CheckConstraint(f"status IN ({_in(DeviceStatus)})", name="status"),
        Index("ix_device_user_id", "user_id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="CASCADE"), nullable=False
    )
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    platform: Mapped[str | None] = mapped_column(String(32), nullable=True)
    model: Mapped[str | None] = mapped_column(String(200), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    first_seen: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_seen: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default=DeviceStatus.ACTIVE)
    bound_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
