"""OTP challenge lifecycle (FA-001, SEC-021).

* 6-digit code from ``secrets``; stored as HMAC-SHA256(pepper, challenge_id || code).
* 5-minute validity; 5 wrong attempts lock the phone for 15 minutes.
* 3 resends per 15-minute window per phone (SPEC FA-001; SEC-021 velocity).
* Single use: verification consumes the challenge; a resend supersedes the previous one.
* Delivery: SMS first; if the provider has not confirmed delivery within 30 s, the same code
  goes out by WhatsApp (delayed check via the scheduler seam).
* Logs carry the masked phone and the challenge id, never the code.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.errors import (
    OtpExpiredError,
    OtpInvalidError,
    OtpLockedError,
    OtpNotFoundError,
    OtpRateLimitedError,
    UserDisabledError,
    UserNotFoundError,
)
from farmerapp.auth.models import OtpChallenge, OtpChannel, OtpPurpose, User, UserStatus
from farmerapp.auth.providers import (
    OTP_TEMPLATE,
    DeliveryStatus,
    ProviderError,
    mask_phone,
    otp_message,
)
from farmerapp.db.session import set_bypass_rls
from farmerapp.logging import get_logger

if TYPE_CHECKING:
    from farmerapp.auth.deps import AuthServices

CHECK_DELIVERY_TASK = "otp.check_delivery"

log = get_logger("farmerapp.auth.otp")


def hash_code(pepper: str, challenge_id: uuid.UUID, code: str) -> str:
    """HMAC-SHA256 keyed with the server pepper, bound to the challenge id."""
    return hmac.new(pepper.encode(), f"{challenge_id}:{code}".encode(), hashlib.sha256).hexdigest()


def generate_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


@dataclass(frozen=True)
class SendResult:
    challenge: OtpChallenge
    resends_left: int


async def find_user_by_phone(session: AsyncSession, phone: str) -> User | None:
    """Cross-tenant lookup used before the tenant is known (auth module only)."""
    await set_bypass_rls(session)
    rows = (
        (
            await session.execute(
                select(User)
                .where(User.phone == phone, User.deleted_at.is_(None))
                .order_by(User.created_at)
            )
        )
        .scalars()
        .all()
    )
    # TODO(FA-008/WC-014): a phone in several tenants needs a tenant picker; take the first.
    return rows[0] if rows else None


class OtpService:
    def __init__(self, services: AuthServices) -> None:
        self._s = services
        services.scheduler.register(CHECK_DELIVERY_TASK, self.check_delivery)

    # ------------------------------------------------------------------ helpers
    @property
    def _now(self) -> datetime:
        return self._s.clock.now()

    async def _latest(self, session: AsyncSession, phone: str, purpose: str) -> OtpChallenge | None:
        """Most recent challenge for the phone (any state); carries the resend window and lock."""
        await set_bypass_rls(session)
        stmt = (
            select(OtpChallenge)
            .where(OtpChallenge.phone == phone, OtpChallenge.purpose == purpose)
            .order_by(OtpChallenge.created_at.desc(), OtpChallenge.resend_count.desc())
            .limit(1)
        )
        return (await session.execute(stmt)).scalar_one_or_none()

    @staticmethod
    def _lock_remaining(challenge: OtpChallenge | None, now: datetime) -> int:
        if challenge is None or challenge.locked_until is None or challenge.locked_until <= now:
            return 0
        return int((challenge.locked_until - now).total_seconds())

    # ------------------------------------------------------------------ send
    async def send(
        self,
        session: AsyncSession,
        *,
        phone: str,
        purpose: OtpPurpose = OtpPurpose.LOGIN,
        device_id: str | None = None,
        tenant_id: uuid.UUID | None = None,
    ) -> SendResult:
        settings = self._s.settings
        now = self._now
        masked = mask_phone(phone)

        user: User | None = None
        if purpose == OtpPurpose.LOGIN:
            user = await find_user_by_phone(session, phone)
            if user is None:
                log.info("otp_send_unknown_user", phone=masked, purpose=purpose)
                raise UserNotFoundError("No account for this number.")
            if user.status != UserStatus.ACTIVE:
                raise UserDisabledError("This account is disabled.")
            tenant_id = user.tenant_id
        if tenant_id is None:
            raise ValueError("tenant_id is required for non-login purposes")

        latest = await self._latest(session, phone, purpose)
        locked = self._lock_remaining(latest, now)
        if locked:
            log.warning("otp_send_locked", phone=masked, retry_after=locked)
            raise OtpLockedError("Too many wrong attempts.", extra={"retry_after": locked})

        resend_count, window_started_at = 0, now
        window = timedelta(seconds=settings.otp_resend_window_seconds)
        if latest is not None and latest.window_started_at + window > now:
            if latest.resend_count >= settings.otp_max_resends:
                retry_after = int((latest.window_started_at + window - now).total_seconds())
                log.warning("otp_rate_limited", phone=masked, retry_after=retry_after)
                raise OtpRateLimitedError(
                    "Too many codes requested. Try again later.",
                    extra={"retry_after": retry_after},
                )
            resend_count = latest.resend_count + 1
            window_started_at = latest.window_started_at
        if latest is not None and latest.consumed_at is None:
            latest.consumed_at = now  # superseded by the new code (single active challenge)

        code = generate_code()
        challenge_id = uuid.uuid4()
        challenge = OtpChallenge(
            id=challenge_id,
            tenant_id=tenant_id,
            created_at=now,
            phone=phone,
            purpose=purpose,
            code_hash=hash_code(settings.otp_pepper, challenge_id, code),
            expires_at=now + timedelta(seconds=settings.otp_ttl_seconds),
            resend_count=resend_count,
            window_started_at=window_started_at,
            channel=OtpChannel.SMS,
            user_id=user.id if user else None,
            device_id=device_id,
        )
        session.add(challenge)

        body = otp_message(code, settings.otp_ttl_seconds)
        try:
            challenge.provider_ref = await self._s.sms.send_sms(phone, body)
            challenge.sms_sent_at = now
        except ProviderError:
            log.exception("otp_sms_failed", phone=masked, challenge_id=str(challenge_id))
            # Fall back to WhatsApp immediately rather than waiting 30 s.
            await self._send_whatsapp(challenge, code, now)
        else:
            self._s.scheduler.schedule(
                CHECK_DELIVERY_TASK,
                now + timedelta(seconds=settings.otp_whatsapp_fallback_seconds),
                # NOTE: the code rides in the in-process payload so the fallback can resend the
                # same one. The Pub/Sub scheduler must not carry it in the clear (KMS envelope
                # or re-issue); see farmerapp.auth.scheduler.
                {"challenge_id": str(challenge_id), "code": code},
            )
        await session.flush()
        log.info(
            "otp_sent",
            phone=masked,
            challenge_id=str(challenge_id),
            purpose=purpose,
            channel=challenge.channel,
            resend_count=resend_count,
            tenant_id=str(tenant_id),
        )
        return SendResult(challenge=challenge, resends_left=settings.otp_max_resends - resend_count)

    async def _send_whatsapp(self, challenge: OtpChallenge, code: str, now: datetime) -> None:
        settings = self._s.settings
        challenge.provider_ref = await self._s.whatsapp.send_whatsapp(
            challenge.phone, OTP_TEMPLATE, {"code": code, "ttl": str(settings.otp_ttl_seconds)}
        )
        challenge.whatsapp_sent_at = now
        challenge.channel = OtpChannel.WHATSAPP
        log.info(
            "otp_fallback_whatsapp",
            phone=mask_phone(challenge.phone),
            challenge_id=str(challenge.id),
        )

    # ------------------------------------------------------------------ delayed check
    async def check_delivery(self, session: AsyncSession, payload: dict[str, Any]) -> None:
        """Scheduled 30 s after an SMS: confirm delivery or resend the same code by WhatsApp."""
        await set_bypass_rls(session)
        challenge = await session.get(OtpChallenge, uuid.UUID(payload["challenge_id"]))
        now = self._now
        if (
            challenge is None
            or challenge.consumed_at is not None
            or challenge.delivered_at is not None
        ):
            return
        if challenge.expires_at <= now:
            return
        status = DeliveryStatus.UNKNOWN
        if challenge.provider_ref:
            status = await self._s.sms.delivery_status(challenge.provider_ref)
        if status == DeliveryStatus.DELIVERED:
            challenge.delivered_at = now
            log.info(
                "otp_delivered", phone=mask_phone(challenge.phone), challenge_id=str(challenge.id)
            )
        elif challenge.whatsapp_sent_at is None:
            log.warning(
                "otp_sms_undelivered",
                phone=mask_phone(challenge.phone),
                challenge_id=str(challenge.id),
                status=status,
            )
            await self._send_whatsapp(challenge, payload["code"], now)
        await session.flush()

    # ------------------------------------------------------------------ verify
    async def verify(
        self,
        session: AsyncSession,
        *,
        phone: str,
        code: str,
        purpose: OtpPurpose = OtpPurpose.LOGIN,
    ) -> OtpChallenge:
        """Consume the active challenge or raise a problem. Attempt counters are committed
        before raising so they survive the error response."""
        settings = self._s.settings
        now = self._now
        masked = mask_phone(phone)
        challenge = await self._latest(session, phone, purpose)
        if challenge is None:
            raise OtpNotFoundError("Request a code first.")
        locked = self._lock_remaining(challenge, now)
        if locked:
            log.warning("otp_verify_locked", phone=masked, retry_after=locked)
            raise OtpLockedError("Too many wrong attempts.", extra={"retry_after": locked})
        if challenge.consumed_at is not None:
            raise OtpNotFoundError("This code was already used. Request a new one.")
        if challenge.expires_at <= now:
            log.info("otp_expired", phone=masked, challenge_id=str(challenge.id))
            raise OtpExpiredError("This code has expired. Request a new one.")

        expected = challenge.code_hash
        supplied = hash_code(settings.otp_pepper, challenge.id, code)
        ok = hmac.compare_digest(expected, supplied)
        dev = settings.otp_dev_code
        if not ok and dev is not None and settings.app_env != "prd":
            ok = hmac.compare_digest(dev, code)
        if not ok:
            challenge.attempts += 1
            attempts_left = settings.otp_max_attempts - challenge.attempts
            if attempts_left <= 0:
                challenge.locked_until = now + timedelta(seconds=settings.otp_lockout_seconds)
                await session.commit()
                log.warning(
                    "otp_locked",
                    phone=masked,
                    challenge_id=str(challenge.id),
                    retry_after=settings.otp_lockout_seconds,
                )
                raise OtpLockedError(
                    "Too many wrong attempts.", extra={"retry_after": settings.otp_lockout_seconds}
                )
            await session.commit()
            log.info(
                "otp_failed",
                phone=masked,
                challenge_id=str(challenge.id),
                attempts_left=attempts_left,
            )
            raise OtpInvalidError("Incorrect code.", extra={"attempts_left": attempts_left})

        challenge.consumed_at = now
        await session.flush()
        log.info("otp_verified", phone=masked, challenge_id=str(challenge.id), purpose=purpose)
        return challenge
