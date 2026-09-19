"""``POST /v1/sync`` — the mobile outbox endpoint (SPEC 8.3, FA-025, NF-003)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Request

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.integrity.deps import integrity_for
from farmerapp.sync import service
from farmerapp.sync.schemas import SyncRequest, SyncResponse
from farmerapp.uploads.router import get_blob_store

router = APIRouter(prefix="/sync", tags=["sync"])

SYNC_ROLES = (Role.FIELD_OFFICER, Role.STORE_MANAGER, Role.CLUSTER_HEAD, Role.FARMER)


@router.post(
    "",
    operation_id="sync",
    # SEC-024: batches with credit sales / payments carry X-Integrity-*; never blocks.
    dependencies=[Depends(integrity_for(None))],
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
        services=services,
        blobs=get_blob_store(request),
        payments=getattr(request.app.state, "payments", None),  # FA-021 payment ops
        diagnosis=getattr(request.app.state, "diagnosis", None),  # M6 offline crop doctor
    )
    changes, cursor, has_more = await service.changes_since(
        session, actor, service.encode_cursor(since)
    )
    service.log_sync_batch(
        actor, device_id=body.device_id, results=results, changes=len(changes), has_more=has_more
    )
    return SyncResponse(results=results, changes=changes, cursor=cursor, has_more=has_more)


__all__ = ["SYNC_ROLES", "router"]
