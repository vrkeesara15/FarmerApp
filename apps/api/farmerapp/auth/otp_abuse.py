"""SEC-021 SMS pumping protection: country rules, velocity rules, block list, cost guard.

An OTP send costs the tenant money and pays an attacker: "SMS pumping" (a.k.a. artificially
inflated traffic) farms premium-rate numbers by driving a login form's send button. FA-001
already limits *resends inside one 15-minute window* per phone; that is not enough — an
attacker walks the window, or walks numbers.

Four layers run in :func:`check_send`, cheapest first, before an SMS is dispatched:

1. **Country** — :func:`check_country`. Only the E.164 prefixes in
   ``OTP_ALLOWED_COUNTRY_CODES`` (``+91``, India, by default) may receive a code, minus
   ``OTP_BLOCKED_COUNTRY_CODES``. A number outside them is ``403 otp_country_blocked``. This
   is the single most effective control: pumping needs foreign premium ranges.
2. **Block list** — :func:`check_blocked`. ``otp_block`` holds a hashed phone or IP with an
   expiry; a match is ``429 otp_blocked``. Rows are written by layer 3 and grow on repeat
   (``OTP_ABUSE_BLOCK_SECONDS`` doubled per strike, capped at 30 days), which is the
   "repeat abuser" rule.
3. **Velocity** — :func:`check_velocity`. Beyond the per-window resend cap: at most
   ``OTP_MAX_SENDS_PER_PHONE_DAY`` sends to one number per 24 h (all purposes) and at most
   ``OTP_MAX_SENDS_PER_IP_HOUR`` sends from one client IP per hour (all numbers). Breaking
   either is ``429 otp_rate_limited`` *and* writes a block row.
4. **Cost guard** — :func:`check_cost`. Tenant sends in the last hour above
   ``OTP_COST_ALERT_PER_HOUR`` log ``otp_cost_alert`` at ERROR (the OPS alert; a login is
   never refused for an alert), and at ``OTP_COST_BLOCK_PER_HOUR`` the breaker opens:
   ``429 otp_cost_limited`` until the hour rolls off.

Everything is counted from ``otp_challenge`` rows, which already exist per send and now
carry ``request_ip``. Nothing here stores a phone or an IP in the clear: ``otp_block`` keys
are ``sha256(pepper || scope || value)`` (:func:`block_key`), so the table is useless to
anyone who reads it and a blocked value can still be looked up in constant work.

Counting is per tenant (RLS). Login sends resolve the phone's tenant first, and an unknown
number never reaches a provider at all (``UserNotFoundError`` in ``OtpService.send``), so the
cross-tenant walk is not a send path. Edge-level limits (per-IP/ASN across tenants, bot
management) stay with Cloud Armor, SEC-014.
"""

from __future__ import annotations

import hashlib
import hmac
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError
from farmerapp.auth.errors import OtpRateLimitedError
from farmerapp.auth.models import OtpBlock, OtpBlockScope, OtpChallenge
from farmerapp.auth.providers import mask_phone
from farmerapp.logging import get_logger
from farmerapp.settings import Settings

log = get_logger("farmerapp.auth.otp_abuse")

#: A block never grows past this, however many strikes (30 days).
MAX_BLOCK_SECONDS = 30 * 86_400
PHONE_WINDOW_SECONDS = 86_400
IP_WINDOW_SECONDS = 3_600
COST_WINDOW_SECONDS = 3_600


class OtpCountryBlockedError(AppError):
    """SEC-021: the number's country may not receive codes (India only by default)."""

    status = 403
    code = "otp_country_blocked"


class OtpBlockedError(AppError):
    """SEC-021: this phone or IP is on the abuse block list."""

    status = 429
    code = "otp_blocked"


class OtpCostLimitedError(AppError):
    """SEC-021 cost guard: the tenant's hourly OTP budget is spent; try again later."""

    status = 429
    code = "otp_cost_limited"


# --------------------------------------------------------------------------- country
def country_prefix(phone: str, prefixes: list[str]) -> str | None:
    """The longest configured prefix ``phone`` starts with (``+91`` for an Indian mobile)."""
    for prefix in sorted(prefixes, key=len, reverse=True):
        if phone.startswith(prefix):
            return prefix
    return None


def check_country(phone: str, settings: Settings) -> None:
    if country_prefix(phone, settings.otp_blocked_country_codes) is not None:
        log.warning("otp_country_blocked", phone=mask_phone(phone), reason="blocklist")
        raise OtpCountryBlockedError("We cannot send a code to this number.")
    if country_prefix(phone, settings.otp_allowed_country_codes) is None:
        log.warning("otp_country_blocked", phone=mask_phone(phone), reason="not_allowed")
        raise OtpCountryBlockedError("We cannot send a code to this number.")


# --------------------------------------------------------------------------- block list
def block_key(pepper: str, scope: OtpBlockScope, value: str) -> str:
    """Keyed hash of a phone or IP: the block list never stores either in the clear."""
    return hmac.new(pepper.encode(), f"{scope.value}:{value}".encode(), hashlib.sha256).hexdigest()


@dataclass(frozen=True)
class BlockDecision:
    scope: OtpBlockScope
    retry_after: int


async def _active_block(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    keys: list[tuple[OtpBlockScope, str]],
    now: datetime,
) -> OtpBlock | None:
    if not keys:
        return None
    stmt = (
        select(OtpBlock)
        .where(
            OtpBlock.tenant_id == tenant_id,
            OtpBlock.key_hash.in_([k for _, k in keys]),
            OtpBlock.blocked_until > now,
        )
        .order_by(OtpBlock.blocked_until.desc())
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


def _keys(settings: Settings, phone: str, ip: str | None) -> list[tuple[OtpBlockScope, str]]:
    keys = [(OtpBlockScope.PHONE, block_key(settings.otp_pepper, OtpBlockScope.PHONE, phone))]
    if ip:
        keys.append((OtpBlockScope.IP, block_key(settings.otp_pepper, OtpBlockScope.IP, ip)))
    return keys


async def check_blocked(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    phone: str,
    request_ip: str | None,
    now: datetime,
    settings: Settings,
) -> None:
    row = await _active_block(session, tenant_id, _keys(settings, phone, request_ip), now)
    if row is None:
        return
    retry_after = max(1, int((row.blocked_until - now).total_seconds()))
    log.warning(
        "otp_blocked",
        phone=mask_phone(phone),
        scope=row.scope,
        strikes=row.strikes,
        retry_after=retry_after,
    )
    raise OtpBlockedError(
        "Too many code requests from this number or device. Try again later.",
        extra={"retry_after": retry_after},
    )


async def record_strike(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    scope: OtpBlockScope,
    value: str,
    reason: str,
    now: datetime,
    settings: Settings,
) -> OtpBlock:
    """Block ``value`` for a doubling window. Repeat abusers stay blocked longer."""
    key = block_key(settings.otp_pepper, scope, value)
    row = (
        await session.execute(
            select(OtpBlock).where(OtpBlock.tenant_id == tenant_id, OtpBlock.key_hash == key)
        )
    ).scalar_one_or_none()
    strikes = (row.strikes + 1) if row is not None else 1
    seconds = min(settings.otp_abuse_block_seconds * (2 ** (strikes - 1)), MAX_BLOCK_SECONDS)
    blocked_until = now + timedelta(seconds=seconds)
    if row is None:
        row = OtpBlock(
            tenant_id=tenant_id,
            scope=scope.value,
            key_hash=key,
            reason=reason,
            strikes=strikes,
            blocked_until=blocked_until,
        )
        session.add(row)
    else:
        row.scope = scope.value
        row.reason = reason
        row.strikes = strikes
        row.blocked_until = blocked_until
    await session.flush()
    log.warning(
        "otp_abuse_block",
        scope=scope.value,
        reason=reason,
        strikes=strikes,
        blocked_seconds=seconds,
        tenant_id=str(tenant_id),
    )
    return row


# --------------------------------------------------------------------------- velocity
async def _sends_since(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    since: datetime,
    *,
    phone: str | None = None,
    request_ip: str | None = None,
) -> int:
    stmt = (
        select(func.count())
        .select_from(OtpChallenge)
        .where(OtpChallenge.tenant_id == tenant_id, OtpChallenge.created_at >= since)
    )
    if phone is not None:
        stmt = stmt.where(OtpChallenge.phone == phone)
    if request_ip is not None:
        stmt = stmt.where(OtpChallenge.request_ip == request_ip)
    return int((await session.scalar(stmt)) or 0)


async def check_velocity(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    phone: str,
    request_ip: str | None,
    now: datetime,
    settings: Settings,
) -> None:
    """Per-phone (24 h) and per-IP (1 h) caps beyond the FA-001 per-window resend limit."""
    per_phone = await _sends_since(
        session, tenant_id, now - timedelta(seconds=PHONE_WINDOW_SECONDS), phone=phone
    )
    if per_phone >= settings.otp_max_sends_per_phone_day:
        await record_strike(
            session,
            tenant_id=tenant_id,
            scope=OtpBlockScope.PHONE,
            value=phone,
            reason="phone_velocity",
            now=now,
            settings=settings,
        )
        log.warning("otp_velocity_phone", phone=mask_phone(phone), sends=per_phone)
        raise OtpRateLimitedError(
            "Too many codes requested for this number today.",
            extra={"retry_after": PHONE_WINDOW_SECONDS},
        )
    if not request_ip:
        return
    per_ip = await _sends_since(
        session, tenant_id, now - timedelta(seconds=IP_WINDOW_SECONDS), request_ip=request_ip
    )
    if per_ip >= settings.otp_max_sends_per_ip_hour:
        await record_strike(
            session,
            tenant_id=tenant_id,
            scope=OtpBlockScope.IP,
            value=request_ip,
            reason="ip_velocity",
            now=now,
            settings=settings,
        )
        log.warning("otp_velocity_ip", sends=per_ip, tenant_id=str(tenant_id))
        raise OtpRateLimitedError(
            "Too many codes requested from this device.",
            extra={"retry_after": IP_WINDOW_SECONDS},
        )


# --------------------------------------------------------------------------- cost guard
async def check_cost(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime,
    settings: Settings,
) -> int:
    """Alert (and, at the hard limit, refuse) when the tenant's hourly OTP spend runs away."""
    sends = await _sends_since(session, tenant_id, now - timedelta(seconds=COST_WINDOW_SECONDS))
    if sends >= settings.otp_cost_block_per_hour:
        log.error(
            "otp_cost_limit",
            tenant_id=str(tenant_id),
            sends_last_hour=sends,
            limit=settings.otp_cost_block_per_hour,
        )
        raise OtpCostLimitedError(
            "We are sending too many codes right now. Try again in a few minutes.",
            extra={"retry_after": COST_WINDOW_SECONDS},
        )
    if sends >= settings.otp_cost_alert_per_hour:
        # OPS alert: a log-based metric on this event pages the on-call (SPEC 12.2).
        log.error(
            "otp_cost_alert",
            tenant_id=str(tenant_id),
            sends_last_hour=sends,
            threshold=settings.otp_cost_alert_per_hour,
        )
    return sends


# --------------------------------------------------------------------------- the gate
async def check_send(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    phone: str,
    request_ip: str | None,
    now: datetime,
    settings: Settings,
) -> None:
    """Every layer, cheapest first. Raises the matching problem; returns None when allowed."""
    check_country(phone, settings)
    await check_blocked(
        session, tenant_id=tenant_id, phone=phone, request_ip=request_ip, now=now, settings=settings
    )
    await check_velocity(
        session, tenant_id=tenant_id, phone=phone, request_ip=request_ip, now=now, settings=settings
    )
    await check_cost(session, tenant_id=tenant_id, now=now, settings=settings)


__all__ = [
    "COST_WINDOW_SECONDS",
    "IP_WINDOW_SECONDS",
    "MAX_BLOCK_SECONDS",
    "PHONE_WINDOW_SECONDS",
    "BlockDecision",
    "OtpBlockedError",
    "OtpCostLimitedError",
    "OtpCountryBlockedError",
    "block_key",
    "check_blocked",
    "check_cost",
    "check_country",
    "check_send",
    "check_velocity",
    "country_prefix",
    "record_strike",
]
