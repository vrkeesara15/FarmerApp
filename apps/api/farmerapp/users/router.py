"""``/v1/users`` and ``/v1/devices`` — user, role and device administration (WC-011).

* Reads (list / get / devices) follow SPEC 2.6 via ``farmerapp.auth.scope``.
* Writes are for owner, director and tenant_admin. Creating a user, changing a role or a
  status, deactivating, forcing a logout, binding a device and reporting one lost need a
  step-up token (SEC-028, ``farmerapp.auth.stepup``); renaming and store / cluster
  assignment do not.
* Only an owner may grant the owner role or change an owner's account; nobody changes their
  own role or status (403 ``role_not_grantable`` / ``cannot_modify_self``).
* Revocation (``farmerapp.auth.devices``): disable / deactivate / force logout set
  ``user.tokens_valid_after`` and revoke every refresh token in the same transaction; a lost
  device's sessions are revoked and its app is told to wipe (SEC-025).
* Every change is audited: ORM changes by the FA-006 listener, plus explicit events
  ``user.force_logout``, ``device.bind`` and ``device.report_lost``.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Path, Request, status
from sqlalchemy import and_, or_, select

from farmerapp.api.errors import AppError, ConflictError, NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import AuthServices, DbSession, Services
from farmerapp.auth.devices import (
    SINGLE_DEVICE_ROLES,
    find_device,
    revoke_sessions,
    user_devices,
)
from farmerapp.auth.models import Device, DeviceStatus, RevokeReason, User, UserRole, UserStatus
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import user_scope
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp, check_step_up
from farmerapp.db import audit
from farmerapp.db.audit import DEVICE_HEADER
from farmerapp.logging import get_logger
from farmerapp.pii.lookup import phone_match
from farmerapp.platform_admin import usage
from farmerapp.platform_admin.plans import Metric
from farmerapp.tenants.models import Cluster, Store
from farmerapp.tenants.settings import get_tenant_settings
from farmerapp.users.schemas import (
    DeviceList,
    DeviceOut,
    DeviceStatusOut,
    ForceLogoutOut,
    UserCreate,
    UserListItem,
    UserOut,
    UserPage,
    UserUpdate,
)

log = get_logger("farmerapp.users")

router = APIRouter(prefix="/users", tags=["users"])
device_router = APIRouter(prefix="/devices", tags=["users"])

READ_ROLES = (Role.OWNER, Role.DIRECTOR, Role.CLUSTER_HEAD, Role.AUDITOR, Role.TENANT_ADMIN)
MANAGE_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)

DeviceIdPath = Annotated[str, Path(min_length=1, max_length=128)]
_STEP_UP = (401, "step_up_required")


class RoleNotGrantableError(AppError):
    status = 403
    code = "role_not_grantable"


class CannotModifySelfError(AppError):
    status = 403
    code = "cannot_modify_self"


class PhoneTakenError(ConflictError):
    code = "phone_taken"


class InvalidAssignmentError(AppError):
    status = 422
    code = "invalid_assignment"


async def _visible_user(session: DbSession, actor: User, user_id: uuid.UUID) -> User:
    """One user of the actor's tenant within the actor's 2.6 scope; everyone sees themselves."""
    stmt = select(User).where(
        User.id == user_id,
        User.tenant_id == actor.tenant_id,
        User.deleted_at.is_(None),
        or_(User.id == actor.id, and_(*user_scope(actor))),
    )
    user = (await session.execute(stmt)).scalar_one_or_none()
    if user is None:
        raise NotFoundError("User not found.")
    return user


def _guard_owner(actor: User, target_role: str | None, new_role: str | None = None) -> None:
    """Only an owner may grant the owner role or change an owner's account."""
    if actor.role == Role.OWNER:
        return
    if Role.OWNER in (target_role, new_role):
        raise RoleNotGrantableError("Only an owner can grant or change the owner role.")


def _guard_self(actor: User, target: User) -> None:
    if actor.id == target.id:
        raise CannotModifySelfError("You cannot change your own role or status.")


async def sign_out_everywhere(
    session: DbSession, services: AuthServices, user: User, reason: RevokeReason, now: datetime
) -> int:
    """Access tokens issued until now stop working at once; every refresh token is revoked."""
    user.tokens_valid_after = now
    revoked = await revoke_sessions(session, user.id, reason, now)
    services.device_cache.invalidate(user.tenant_id, user.id)
    await session.flush()
    return revoked


async def _disable(
    session: DbSession, services: AuthServices, actor: User, user: User, now: datetime
) -> None:
    user.status = UserStatus.DISABLED
    revoked = await sign_out_everywhere(session, services, user, RevokeReason.USER_DISABLED, now)
    log.info(
        "user_disabled",
        actor_id=str(actor.id),
        user_id=str(user.id),
        tenant_id=str(user.tenant_id),
        revoked_sessions=revoked,
    )


async def _check_assignment(
    session: DbSession, store_id: uuid.UUID | None, cluster_id: uuid.UUID | None
) -> None:
    if store_id is not None and await session.get(Store, store_id) is None:
        raise InvalidAssignmentError("Unknown store.", extra={"field": "store_id"})
    if cluster_id is not None and await session.get(Cluster, cluster_id) is None:
        raise InvalidAssignmentError("Unknown cluster.", extra={"field": "cluster_id"})


# --------------------------------------------------------------------------- users
@router.get(
    "",
    operation_id="listUsers",
    summary="Users of the caller's tenant with device status (cluster heads: own cluster)",
    response_model=UserPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_users(
    actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession, page: Page
) -> UserPage:
    stmt = select(User).where(User.deleted_at.is_(None), *user_scope(actor))
    after = page.after(User.created_at, User.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(User.created_at, User.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    # Device status for the whole page in one query (C101 shows it per row).
    devices: dict[uuid.UUID, list[Device]] = {u.id: [] for u in items}
    if devices:
        found = await session.execute(
            select(Device).where(
                Device.tenant_id == actor.tenant_id,
                Device.user_id.in_(list(devices)),
                Device.deleted_at.is_(None),
            )
        )
        for d in found.scalars():
            devices[d.user_id].append(d)
    return UserPage(
        items=[UserListItem.from_user_devices(u, devices[u.id]) for u in items],
        next_cursor=next_cursor,
    )


@router.post(
    "",
    operation_id="createUser",
    summary="Create a staff account (WC-011; step-up required)",
    status_code=status.HTTP_201_CREATED,
    response_model=UserOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(
        _STEP_UP,
        (403, "role_not_grantable"),
        (409, "phone_taken"),
        (409, "plan_limit_exceeded"),  # WC-014
        (422, "invalid_assignment"),
    ),
)
async def create_user(
    body: UserCreate,
    actor: Annotated[User, require_roles(*MANAGE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
) -> UserOut:
    _guard_owner(actor, None, body.role)
    await _check_assignment(session, body.store_id, body.cluster_id)
    taken = await session.scalar(
        select(User.id).where(User.tenant_id == actor.tenant_id, phone_match(User, body.phone))
    )
    if taken is not None:
        raise PhoneTakenError("A user with this phone number already exists.")
    # WC-014: field officers are what a plan is sized and priced by (SPEC 7: 5,000 officers
    # across 50 tenants); other staff roles are not capped.
    if UserRole(body.role) is UserRole.FIELD_OFFICER:
        await usage.check_and_record(session, actor.tenant_id, Metric.OFFICERS)
    settings = await get_tenant_settings(session, actor.tenant_id)
    language = body.language or settings.default_language
    user = User(
        id=uuid.uuid4(),
        tenant_id=actor.tenant_id,
        phone=body.phone,
        name=body.name,
        role=body.role,
        store_id=body.store_id,
        cluster_id=body.cluster_id,
        language=language,
        status=UserStatus.ACTIVE,
    )
    session.add(user)
    await session.flush()
    await session.refresh(user)
    log.info("user_created", actor_id=str(actor.id), user_id=str(user.id), role=user.role)
    return UserOut.from_user(user)


@router.get(
    "/{id}",
    operation_id="getUser",
    summary="One user (management roles within their scope, or the user themselves)",
    response_model=UserOut,
    responses=problem_responses((404, "not_found")),
)
async def get_user(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*READ_ROLES, self_param="id")],
    session: DbSession,
) -> UserOut:
    return UserOut.from_user(await _visible_user(session, actor, id))


@router.patch(
    "/{id}",
    operation_id="updateUser",
    summary="Change name, role, status, store or cluster (role / status need step-up)",
    response_model=UserOut,
    responses=problem_responses(
        (404, "not_found"),
        _STEP_UP,
        (403, "role_not_grantable"),
        (403, "cannot_modify_self"),
    ),
)
async def update_user(
    id: uuid.UUID,
    body: UserUpdate,
    request: Request,
    actor: Annotated[User, require_roles(*MANAGE_ROLES)],
    session: DbSession,
    services: Services,
) -> UserOut:
    user = await _visible_user(session, actor, id)
    changes = body.model_dump(exclude_unset=True)
    sensitive = {"role", "status"} & set(changes)
    if sensitive:
        check_step_up(request, services, actor)  # SEC-028
        _guard_self(actor, user)
        _guard_owner(actor, user.role, changes.get("role"))
    now = services.clock.now()
    # WC-014: keep the officer counter honest when a role moves in or out of field_officer.
    new_role = changes.get("role")
    if new_role is not None and new_role != user.role:
        was, becomes = UserRole(user.role), UserRole(new_role)
        if becomes is UserRole.FIELD_OFFICER and was is not UserRole.FIELD_OFFICER:
            await usage.check_and_record(session, user.tenant_id, Metric.OFFICERS)
        elif was is UserRole.FIELD_OFFICER and becomes is not UserRole.FIELD_OFFICER:
            await usage.record(session, user.tenant_id, Metric.OFFICERS, -1)
    disabling = changes.get("status") == UserStatus.DISABLED and user.status != UserStatus.DISABLED
    for field, value in changes.items():
        if field != "status" or not disabling:
            setattr(user, field, value)
    if disabling:
        await _disable(session, services, actor, user, now)
    await session.flush()
    log.info(
        "user_updated",
        actor_id=str(actor.id),
        user_id=str(user.id),
        tenant_id=str(user.tenant_id),
        fields=sorted(changes),
    )
    return UserOut.from_user(user)


@router.post(
    "/{id}/deactivate",
    operation_id="deactivateUser",
    summary="Disable an account: signed out everywhere, apps wipe local data (step-up)",
    response_model=UserOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(
        (404, "not_found"), _STEP_UP, (403, "role_not_grantable"), (403, "cannot_modify_self")
    ),
)
async def deactivate_user(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*MANAGE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> UserOut:
    user = await _visible_user(session, actor, id)
    _guard_self(actor, user)
    _guard_owner(actor, user.role)
    if user.status != UserStatus.DISABLED:
        await _disable(session, services, actor, user, services.clock.now())
    return UserOut.from_user(user)


@router.post(
    "/{id}/force-logout",
    operation_id="forceLogoutUser",
    summary="Sign a user out of every device within the revocation window (step-up)",
    response_model=ForceLogoutOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses((404, "not_found"), _STEP_UP, (403, "role_not_grantable")),
)
async def force_logout(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*MANAGE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> ForceLogoutOut:
    user = await _visible_user(session, actor, id)
    _guard_owner(actor, user.role)
    now = services.clock.now()
    revoked = await sign_out_everywhere(session, services, user, RevokeReason.FORCE_LOGOUT, now)
    audit.record(
        session,
        action="user.force_logout",
        entity="user",
        entity_id=user.id,
        after={"revoked_sessions": revoked, "tokens_valid_after": now},
    )
    await session.flush()
    log.info("user_force_logout", actor_id=str(actor.id), user_id=str(user.id), revoked=revoked)
    return ForceLogoutOut(user_id=user.id, revoked_sessions=revoked, tokens_valid_after=now)


# --------------------------------------------------------------------------- devices
@router.get(
    "/{id}/devices",
    operation_id="listUserDevices",
    summary="Devices a user has signed in from (pending ones await binding)",
    response_model=DeviceList,
    responses=problem_responses((404, "not_found")),
)
async def list_user_devices(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
) -> DeviceList:
    user = await _visible_user(session, actor, id)
    return DeviceList(items=[DeviceOut.from_row(d) for d in await user_devices(session, user.id)])


@router.post(
    "/{id}/devices/{device_id}/bind",
    operation_id="bindUserDevice",
    summary="Bind a device (field officers: unbinds and signs out the previous one; step-up)",
    response_model=DeviceOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses((404, "not_found"), _STEP_UP, (403, "role_not_grantable")),
)
async def bind_device(
    id: uuid.UUID,
    device_id: DeviceIdPath,
    actor: Annotated[User, require_roles(*MANAGE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> DeviceOut:
    user = await _visible_user(session, actor, id)
    _guard_owner(actor, user.role)
    now = services.clock.now()
    unbound: list[str] = []
    if UserRole(user.role) in SINGLE_DEVICE_ROLES:
        others = await session.execute(
            select(Device).where(
                Device.user_id == user.id,
                Device.device_id != device_id,
                Device.status == DeviceStatus.ACTIVE,
                Device.deleted_at.is_(None),
            )
        )
        for other in others.scalars():
            other.status = DeviceStatus.REVOKED
            other.revoked_at = now
            await revoke_sessions(
                session, user.id, RevokeReason.DEVICE_REVOKED, now, device_id=other.device_id
            )
            unbound.append(other.device_id)
    row = await find_device(session, user.id, device_id)
    if row is None:
        row = Device(
            id=uuid.uuid4(),
            tenant_id=user.tenant_id,
            user_id=user.id,
            device_id=device_id,
            first_seen=now,
            last_seen=now,
        )
        session.add(row)
    row.status = DeviceStatus.ACTIVE
    row.bound_at = now
    row.revoked_at = None
    await session.flush()
    services.device_cache.invalidate(user.tenant_id, user.id)
    audit.record(
        session,
        action="device.bind",
        entity="device",
        entity_id=row.id,
        after={"user_id": user.id, "device_id": device_id, "unbound": unbound},
    )
    await session.flush()
    await session.refresh(row)
    return DeviceOut.from_row(row)


@router.post(
    "/{id}/devices/{device_id}/report-lost",
    operation_id="reportUserDeviceLost",
    summary="Mark a device lost: its sessions end and its app wipes local data (step-up)",
    response_model=DeviceOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses((404, "not_found"), _STEP_UP, (403, "role_not_grantable")),
)
async def report_device_lost(
    id: uuid.UUID,
    device_id: DeviceIdPath,
    actor: Annotated[User, require_roles(*MANAGE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> DeviceOut:
    user = await _visible_user(session, actor, id)
    _guard_owner(actor, user.role)
    row = await find_device(session, user.id, device_id)
    if row is None:
        raise NotFoundError("Device not found.")
    now = services.clock.now()
    row.status = DeviceStatus.LOST
    row.revoked_at = now
    revoked = await revoke_sessions(
        session, user.id, RevokeReason.DEVICE_LOST, now, device_id=device_id
    )
    services.device_cache.invalidate(user.tenant_id, user.id)
    audit.record(
        session,
        action="device.report_lost",
        entity="device",
        entity_id=row.id,
        after={"user_id": user.id, "device_id": device_id, "revoked_sessions": revoked},
    )
    await session.flush()
    await session.refresh(row)
    log.warning("device_reported_lost", actor_id=str(actor.id), user_id=str(user.id))
    return DeviceOut.from_row(row)


@device_router.get(
    "/me/status",
    operation_id="getMyDeviceStatus",
    summary="SEC-025: this device's status; the apps poll it on start and wipe when told",
    response_model=DeviceStatusOut,
)
async def my_device_status(
    request: Request,
    user: Annotated[User, require_roles(*Role)],
    session: DbSession,
) -> DeviceStatusOut:
    device_id: str | None = getattr(request.state, "device_id", None) or (
        request.headers.get(DEVICE_HEADER) or None
    )
    row = await find_device(session, user.id, device_id[:128]) if device_id else None
    device_status = row.status if row is not None else "unknown"
    return DeviceStatusOut(
        device_id=device_id[:128] if device_id else None,
        status=device_status,
        wipe_required=device_status == DeviceStatus.LOST,
        user_status="active",
    )
