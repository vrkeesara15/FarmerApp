"""``POST /v1/location/batch`` — the REST twin of the ``location_batch`` sync op (FA-010)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Request

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.location.ingest import LocationBatchIn, LocationBatchOut, ingest_batch

batch_router = APIRouter(prefix="/location", tags=["duty"])


@batch_router.post(
    "/batch",
    operation_id="uploadLocationBatch",
    summary="Upload up to 500 on-duty location points of the caller's duty session",
    response_model=LocationBatchOut,
    responses=problem_responses((404, "not_found"), (422, "idempotency_key_reuse")),
)
@idempotent(status_code=200)
async def upload_location_batch(
    request: Request,
    body: LocationBatchIn,
    actor: Annotated[User, require_roles(Role.FIELD_OFFICER)],
    session: DbSession,
    services: Services,
) -> LocationBatchOut:
    return await ingest_batch(session, actor, body, received_at=services.clock.now())


__all__ = ["batch_router"]
