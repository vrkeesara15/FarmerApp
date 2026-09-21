"""Auth service container and FastAPI dependencies (``get_current_user``)."""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass, field
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import UnauthenticatedError
from farmerapp.auth.clock import Clock, SystemClock
from farmerapp.auth.devices import DeviceStatusCache
from farmerapp.auth.errors import DeviceWipeRequiredError, SessionRevokedError, UserDisabledError
from farmerapp.auth.models import DeviceStatus, User, UserStatus
from farmerapp.auth.otp import OtpService
from farmerapp.auth.providers import FakeProvider, MockServerProvider, SmsProvider, WhatsAppProvider
from farmerapp.auth.scheduler import InProcessScheduler, Scheduler
from farmerapp.auth.tokens import TokenService
from farmerapp.db import audit
from farmerapp.db.session import get_session, get_session_factory, set_tenant
from farmerapp.platform_admin.errors import TenantSuspendedError
from farmerapp.platform_admin.state import get_tenant_state
from farmerapp.settings import Settings


@dataclass
class AuthServices:
    settings: Settings
    clock: Clock
    sms: SmsProvider
    whatsapp: WhatsAppProvider
    scheduler: Scheduler
    otp: OtpService = field(init=False)
    tokens: TokenService = field(init=False)
    device_cache: DeviceStatusCache = field(init=False)

    def __post_init__(self) -> None:
        self.otp = OtpService(self)
        self.tokens = TokenService(self)
        self.device_cache = DeviceStatusCache(self.clock, self.settings.security_cache_ttl_seconds)


def build_auth_services(settings: Settings) -> AuthServices:
    """Wire providers from settings. Prod adapters (DLT SMS, WhatsApp Business) plug in here."""
    clock = SystemClock()
    if settings.otp_provider == "fake":
        fake = FakeProvider()
        return AuthServices(
            settings=settings,
            clock=clock,
            sms=fake,
            whatsapp=fake,
            scheduler=InProcessScheduler(clock),
        )
    mock = MockServerProvider(
        sms_url=settings.sms_provider_url, whatsapp_url=settings.whatsapp_provider_url
    )
    return AuthServices(
        settings=settings, clock=clock, sms=mock, whatsapp=mock, scheduler=InProcessScheduler(clock)
    )


SessionProvider = Callable[[], contextlib.AbstractAsyncContextManager[AsyncSession]]


@contextlib.asynccontextmanager
async def _job_session() -> AsyncIterator[AsyncSession]:
    """A transaction for scheduled auth tasks; each task binds the tenant from its payload."""
    factory = get_session_factory()
    async with factory() as session, session.begin():
        yield session


async def tick(
    scheduler: InProcessScheduler, session_provider: SessionProvider = _job_session
) -> int:
    """One scheduler pass: run due tasks inside a session. Called every second by the lifespan."""
    if not scheduler.has_due():
        return 0
    async with session_provider() as session:
        return await scheduler.run_due(session)


def get_auth_services(request: Request) -> AuthServices:
    services: AuthServices = request.app.state.auth
    return services


async def get_current_user(
    request: Request,
    session: Annotated[AsyncSession, Depends(get_session)],
    services: Annotated[AuthServices, Depends(get_auth_services)],
) -> User:
    """Verify the bearer token, bind the tenant on the session and return the active user.

    The tenant is bound *before* the user is loaded, so RLS hides the user when the token's
    tenant claim does not match: a forged claim is just an unknown user (401). Once the user
    is known it becomes the audit actor for everything this request writes (FA-006).

    Revocation (WC-011, SEC-025; see ``farmerapp.auth.devices``): a disabled account or a
    token issued at or before ``user.tokens_valid_after`` is rejected at once (the row is
    read on every request); a token bound to a device (``did``) is rejected when the device
    is lost (401 ``device_wipe_required``) or revoked (401 ``session_revoked``), read through
    the device status cache (TTL <= 60 s).
    """
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not token:
        raise UnauthenticatedError("Bearer token required.", headers={"WWW-Authenticate": "Bearer"})
    claims = services.tokens.decode_access_token(token, services.clock.now())

    await set_tenant(session, claims.tenant_id)
    request.state.tenant_id = claims.tenant_id
    user = await session.get(User, claims.user_id)
    if user is None or user.tenant_id != claims.tenant_id or user.deleted_at is not None:
        raise UnauthenticatedError("Unknown user.")
    challenge = {"WWW-Authenticate": "Bearer"}
    if user.status != UserStatus.ACTIVE and claims.device_id is not None:
        raise DeviceWipeRequiredError("This account is disabled.", headers=challenge)
    if user.status != UserStatus.ACTIVE:
        # The session is no longer valid: 401 so clients drop their tokens and re-login
        # (where they get 403 `user_disabled` with the reason).
        raise UnauthenticatedError(
            "This account is disabled.",
            code=UserDisabledError.code,
            headers={"WWW-Authenticate": "Bearer"},
        )
    valid_after = user.tokens_valid_after
    if valid_after is not None and claims.issued_at <= int(valid_after.timestamp()):
        raise SessionRevokedError("You were signed out by an administrator.", headers=challenge)
    if claims.device_id is not None:
        device_status = await services.device_cache.status(
            session, user.tenant_id, user.id, claims.device_id
        )
        if device_status == DeviceStatus.LOST:
            raise DeviceWipeRequiredError("This device was reported lost.", headers=challenge)
        if device_status == DeviceStatus.REVOKED:
            raise SessionRevokedError("This device is no longer bound.", headers=challenge)
        request.state.device_id = claims.device_id
    # WC-014: a suspended or archived tenant works for nobody, whatever their role. Read from
    # the per-process tenant-state cache (TTL <= 60 s), so this costs no query in the common
    # case; the platform admin who suspended the tenant already revoked its sessions, this is
    # the belt to that braces.
    tenant_state = await get_tenant_state(session, user.tenant_id)
    if tenant_state.blocked:
        raise TenantSuspendedError(f"This workspace is {tenant_state.status}.")
    request.state.tenant_state = tenant_state
    request.state.user = user
    audit.bind_actor(audit.actor_from_request(request, user))
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
Services = Annotated[AuthServices, Depends(get_auth_services)]
DbSession = Annotated[AsyncSession, Depends(get_session)]

__all__ = [
    "AuthServices",
    "CurrentUser",
    "DbSession",
    "Services",
    "build_auth_services",
    "get_auth_services",
    "get_current_user",
    "tick",
]

_ = uuid  # re-exported types use uuid in annotations
