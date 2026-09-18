from __future__ import annotations

from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel

from farmerapp import __version__
from farmerapp.auth.policy import PUBLIC
from farmerapp.settings import get_settings

router = APIRouter(tags=["health"])


class HealthResponse(BaseModel):
    status: Literal["ok"]
    service: str
    version: str
    env: str


@router.get(
    "/health",
    operation_id="getHealth",
    summary="Liveness probe",
    dependencies=[PUBLIC],
    response_model=HealthResponse,
)
async def get_health() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(
        status="ok", service=settings.service_name, version=__version__, env=settings.app_env
    )
