"""``POST /v1/sync`` — the mobile outbox endpoint (SPEC 8.3, FA-025, NF-003)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Request

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.sync import service
from farmerapp.sync.schemas import SyncRequest, SyncResponse

router = APIRouter(prefix="/sync", tags=["sync"])

SYNC_ROLES = (Role.FIELD_OFFICER, Role.STORE_MANAGER, Role.CLUSTER_HEAD, Role.FARMER)


@router.post(
    "",
    operation_id="sync",
    summary="Apply a batch of outbox operations and return server changes since a cursor",
    response_model=SyncResponse,
    responses=problem_responses((400, "invalid_cursor"), (422, "idempotency_key_reuse")),
)
@idempotent(status_code=200)
async def sync(
    request: Request,
    body: SyncRequest,
    actor: Annotated[User, require_roles(*SYNC_ROLES)],
    session: DbSession,
    services: Services,
) -> SyncResponse:
    since = service.decode_cursor(body.cursor)  # reject a bad cursor before applying anything
    results = await service.apply_ops(
        session,
        actor,
        device_id=body.device_id,
        ops=body.ops,
        settings=services.settings,
        now=services.clock.now(),
    )
    changes, cursor, has_more = await service.changes_since(
        session, actor, service.encode_cursor(since)
    )
    return SyncResponse(results=results, changes=changes, cursor=cursor, has_more=has_more)


__all__ = ["SYNC_ROLES", "router"]
