"""Device binding, the device-status cache and session revocation (WC-011, SEC-020, SEC-025).

**Binding (SEC-020).** Every login and refresh that carries a ``device_id`` upserts a
``device`` row (first / last seen, platform, model, app version). A field officer has at most
one ``active`` device: a login from another device is refused with 409 ``device_not_bound``
and recorded as ``pending`` so the console can offer "Bind this device"
(``POST /v1/users/{id}/devices/{device_id}/bind``). Other roles may use several devices.

**Revocation within 5 minutes (WC-011 acceptance).** Three server-side checks back the 15-min
access token:

* ``user.status`` and ``user.tokens_valid_after`` are read from the user row that
  ``get_current_user`` loads on every request: a disabled or force-logged-out user is
  rejected on their very next request (0 s).
* a device's status (``lost`` / ``revoked``) is read through ``DeviceStatusCache``, an
  in-process cache with a TTL of ``security_cache_ttl_seconds`` (default 30 s, at most 60 s).
  The instance that handles the admin action drops its entry at once; other instances see the
  change when their entry expires. Worst case: TTL (<= 60 s) — well under 5 minutes.
* refresh tokens are revoked in the same transaction as the admin action (``revoked_reason``),
  so a refresh fails immediately.

**Remote wipe (SEC-025).** A request whose access token is bound to a device (``did`` claim)
gets 401 ``device_wipe_required`` when the account is disabled or the device is reported
lost; refresh answers the same. The app must wipe its local data on that code.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import Clock
from farmerapp.auth.errors import (
    DeviceIdRequiredError,
    DeviceNotBoundError,
    DeviceWipeRequiredError,
)
from farmerapp.auth.models import Device, DeviceStatus, RefreshToken, RevokeReason, User, UserRole
from farmerapp.logging import get_logger

log = get_logger("farmerapp.auth.devices")

#: Roles bound to a single device (SEC-020 "device-bound refresh for field agents").
SINGLE_DEVICE_ROLES = frozenset({UserRole.FIELD_OFFICER})

CacheKey = tuple[uuid.UUID, uuid.UUID, str]


@dataclass(frozen=True)
class DeviceMeta:
    """What the app tells us about itself at login / refresh (all optional)."""

    platform: str | None = None
    model: str | None = None
    app_version: str | None = None


class DeviceStatusCache:
    """``(tenant, user, device id) -> status`` with a TTL, per process (see module doc)."""

    def __init__(self, clock: Clock, ttl_seconds: int) -> None:
        if ttl_seconds > 60:
            raise ValueError("the device status cache TTL must be at most 60 s")
        self._clock = clock
        self._ttl = timedelta(seconds=ttl_seconds)
        self._entries: dict[CacheKey, tuple[datetime, str | None]] = {}

    @property
    def ttl(self) -> timedelta:
        return self._ttl

    async def status(
        self, session: AsyncSession, tenant_id: uuid.UUID, user_id: uuid.UUID, device_id: str
    ) -> str | None:
        """The device's status (``None``: never seen), from the cache while fresh."""
        key = (tenant_id, user_id, device_id)
        now = self._clock.now()
        hit = self._entries.get(key)
        if hit is not None and hit[0] > now:
            return hit[1]
        value = await session.scalar(
            select(Device.status).where(
                Device.tenant_id == tenant_id,
                Device.user_id == user_id,
                Device.device_id == device_id,
                Device.deleted_at.is_(None),
            )
        )
        if self._ttl.total_seconds() > 0:
            if len(self._entries) > 10_000:  # bounded: drop everything rather than grow
                self._entries.clear()
            self._entries[key] = (now + self._ttl, value)
        return value

    def invalidate(self, tenant_id: uuid.UUID, user_id: uuid.UUID) -> None:
        """Forget every device of a user (called by the instance handling the admin action)."""
        for key in [k for k in self._entries if k[0] == tenant_id and k[1] == user_id]:
            del self._entries[key]

    def clear(self) -> None:
        self._entries.clear()


# --------------------------------------------------------------------------- rows
async def find_device(session: AsyncSession, user_id: uuid.UUID, device_id: str) -> Device | None:
    return (
        await session.execute(
            select(Device).where(
                Device.user_id == user_id,
                Device.device_id == device_id,
                Device.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


async def user_devices(session: AsyncSession, user_id: uuid.UUID) -> list[Device]:
    rows = await session.execute(
        select(Device)
        .where(Device.user_id == user_id, Device.deleted_at.is_(None))
        .order_by(Device.last_seen.desc(), Device.id)
    )
    return list(rows.scalars())


def _apply_meta(row: Device, meta: DeviceMeta, now: datetime) -> None:
    row.last_seen = now
    if meta.platform:
        row.platform = meta.platform
    if meta.model:
        row.model = meta.model
    if meta.app_version:
        row.app_version = meta.app_version


def _new_device(user: User, device_id: str, meta: DeviceMeta, now: datetime, status: str) -> Device:
    return Device(
        id=uuid.uuid4(),
        tenant_id=user.tenant_id,
        user_id=user.id,
        device_id=device_id,
        platform=meta.platform,
        model=meta.model,
        app_version=meta.app_version,
        first_seen=now,
        last_seen=now,
        status=status,
        bound_at=now if status == DeviceStatus.ACTIVE else None,
    )


async def admit_login(
    session: AsyncSession,
    user: User,
    *,
    device_id: str | None,
    meta: DeviceMeta,
    now: datetime,
) -> Device | None:
    """SEC-020 gate at login: record the device and refuse what is not allowed.

    Raises 401 ``device_wipe_required`` for a device reported lost, 409 ``device_not_bound``
    when a field officer signs in from a device other than their bound one (the attempt is
    committed as ``pending`` first so an admin can bind it), 422 ``device_id_required`` when a
    field officer signs in without a device id.
    """
    single = UserRole(user.role) in SINGLE_DEVICE_ROLES
    if device_id is None:
        if single:
            raise DeviceIdRequiredError("Field officers must sign in from the app.")
        return None
    row = await find_device(session, user.id, device_id)
    if row is not None and row.status == DeviceStatus.LOST:
        log.warning("login_from_lost_device", user_id=str(user.id))
        raise DeviceWipeRequiredError("This device was reported lost.")

    if single and (row is None or row.status != DeviceStatus.ACTIVE):
        other = await session.scalar(
            select(Device.id).where(
                Device.user_id == user.id,
                Device.device_id != device_id,
                Device.status == DeviceStatus.ACTIVE,
                Device.deleted_at.is_(None),
            )
        )
        if other is not None or (row is not None and row.status == DeviceStatus.REVOKED):
            if row is None:
                row = _new_device(user, device_id, meta, now, DeviceStatus.PENDING)
                session.add(row)
            else:
                _apply_meta(row, meta, now)
                row.status = DeviceStatus.PENDING
            await session.commit()  # keep the pending row for the console; the login fails
            log.warning("device_not_bound", user_id=str(user.id), device=str(row.id))
            raise DeviceNotBoundError(
                "This account is bound to another device. Ask your administrator to bind this one."
            )

    if row is None:
        row = _new_device(user, device_id, meta, now, DeviceStatus.ACTIVE)
        session.add(row)
    else:
        _apply_meta(row, meta, now)
        if row.status != DeviceStatus.ACTIVE:
            row.status = DeviceStatus.ACTIVE
            row.bound_at = now
            row.revoked_at = None
    await session.flush()
    return row


async def check_refresh(
    session: AsyncSession, user: User, device_id: str, meta: DeviceMeta, now: datetime
) -> None:
    """At refresh: a lost device must wipe; otherwise note that the device is alive."""
    row = await find_device(session, user.id, device_id)
    if row is None:
        return
    if row.status == DeviceStatus.LOST:
        raise DeviceWipeRequiredError("This device was reported lost.")
    _apply_meta(row, meta, now)


async def revoke_sessions(
    session: AsyncSession,
    user_id: uuid.UUID,
    reason: RevokeReason,
    now: datetime,
    *,
    device_id: str | None = None,
) -> int:
    """Revoke every live refresh token of the user (or of one of their devices)."""
    stmt = (
        update(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now, revoked_reason=reason.value)
    )
    if device_id is not None:
        stmt = stmt.where(RefreshToken.device_id == device_id)
    result = await session.execute(stmt.execution_options(synchronize_session="fetch"))
    return int(getattr(result, "rowcount", 0) or 0)


__all__ = [
    "SINGLE_DEVICE_ROLES",
    "DeviceMeta",
    "DeviceStatusCache",
    "admit_login",
    "check_refresh",
    "find_device",
    "revoke_sessions",
    "user_devices",
]
