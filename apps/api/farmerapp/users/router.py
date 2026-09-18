"""``/v1/users`` — list, read and update staff/farmer accounts of the caller's tenant.

Minimal slice of WC-011 (users, roles, device binding, forced logout) so FA-002 has real
policies to test. Read scope follows SPEC 2.6 via ``farmerapp.auth.scope``; pagination is
the shared keyset cursor. Role/status changes will require re-auth and an audit row
(SEC-028, FA-006) when those land.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter
from sqlalchemy import and_, or_, select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import user_scope
from farmerapp.logging import get_logger
from farmerapp.users.schemas import UserOut, UserPage, UserUpdate

log = get_logger("farmerapp.users")

router = APIRouter(prefix="/users", tags=["users"])

READ_ROLES = (Role.OWNER, Role.DIRECTOR, Role.CLUSTER_HEAD, Role.AUDITOR, Role.TENANT_ADMIN)
MANAGE_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)


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


@router.get(
    "",
    operation_id="listUsers",
    summary="Users of the caller's tenant (cluster heads see their own cluster)",
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
    return UserPage(items=[UserOut.from_user(u) for u in items], next_cursor=next_cursor)


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
    summary="Change name, role, status, store or cluster of a user",
    response_model=UserOut,
    responses=problem_responses((404, "not_found")),
)
async def update_user(
    id: uuid.UUID,
    body: UserUpdate,
    actor: Annotated[User, require_roles(*MANAGE_ROLES)],
    session: DbSession,
) -> UserOut:
    user = await _visible_user(session, actor, id)
    changes = body.model_dump(exclude_unset=True)
    for field, value in changes.items():
        setattr(user, field, value)
    await session.flush()
    log.info(
        "user_updated",
        actor_id=str(actor.id),
        user_id=str(user.id),
        tenant_id=str(user.tenant_id),
        fields=sorted(changes),
    )
    return UserOut.from_user(user)
