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
from farmerapp.auth.errors import UserDisabledError
from farmerapp.auth.models import User, UserStatus
from farmerapp.auth.otp import OtpService
from farmerapp.auth.providers import FakeProvider, MockServerProvider, SmsProvider, WhatsAppProvider
from farmerapp.auth.scheduler import InProcessScheduler, Scheduler
from farmerapp.auth.tokens import TokenService
from farmerapp.db.session import get_session, get_session_factory, set_bypass_rls, set_tenant
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

    def __post_init__(self) -> None:
        self.otp = OtpService(self)
        self.tokens = TokenService(self)


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
    """A transaction for scheduled auth tasks (no request, no tenant: auth-module bypass)."""
    factory = get_session_factory()
    async with factory() as session, session.begin():
        await set_bypass_rls(session)
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
    """Verify the bearer token, bind the tenant on the session and return the active user."""
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
    if user.status != UserStatus.ACTIVE:
        # The session is no longer valid: 401 so clients drop their tokens and re-login
        # (where they get 403 `user_disabled` with the reason).
        raise UnauthenticatedError(
            "This account is disabled.",
            code=UserDisabledError.code,
            headers={"WWW-Authenticate": "Bearer"},
        )
    request.state.user = user
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
