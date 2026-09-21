"""AN-016 routes.

* ``POST /v1/analytics/ask {question}`` — owner, director, cluster head (own cluster only).
* ``GET  /v1/analytics/ask/views`` — the authorised view catalogue, so the console can show
  what the assistant is able to answer without guessing.

A question that cannot be answered is **200 with ``answered: false``**, not an error: the
caller gets the friendly headline (``message_key``), the reason, and the SQL that was
attempted. Only an unconfigured assistant is a 503.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Request

from farmerapp.api.errors import AppError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.nlq import service
from farmerapp.nlq.llm import NlqClient, build_client
from farmerapp.nlq.schemas import AskIn, AskOut, AskViewColumnOut, AskViewOut, AskViewsOut
from farmerapp.nlq.views import VIEWS

router = APIRouter(prefix="/analytics/ask", tags=["analytics"])

ASK_ROLES = (Role.OWNER, Role.DIRECTOR, Role.CLUSTER_HEAD)


class AskUnavailableError(AppError):
    status = 503
    code = "ask_unavailable"


def get_client(request: Request) -> NlqClient:
    """The app's question writer (built on first use; tests put their own on app.state)."""
    client: NlqClient | None = getattr(request.app.state, "nlq_client", None)
    if client is None:
        client = build_client(request.app.state.auth.settings)
        request.app.state.nlq_client = client
    return client


@router.post(
    "",
    operation_id="askAnalytics",
    summary="AN-016: ask a question in words; read-only SQL over authorised views",
    response_model=AskOut,
    responses=problem_responses((503, "ask_unavailable")),
)
async def ask(
    body: AskIn,
    request: Request,
    actor: Annotated[User, require_roles(*ASK_ROLES)],
    session: DbSession,
    services: Services,
) -> AskOut:
    client = get_client(request)
    if client.provider == "off":
        raise AskUnavailableError("The assistant is not configured.")
    settings = services.settings
    result = await service.ask(
        session,
        actor,
        body.question,
        client=client,
        row_limit=settings.nlq_row_limit,
        statement_timeout_ms=settings.nlq_statement_timeout_ms,
        now=services.clock.now(),
    )
    return AskOut(
        answered=result.answered,
        question=result.question,
        answer=result.answer,
        reason=result.reason,
        message_key=result.message_key,
        sql=result.sql,
        views=result.views,
        columns=result.columns,
        rows=result.rows,
        row_count=result.row_count,
        truncated=result.truncated,
        scope=result.scope,
        model=result.model,
        elapsed_ms=result.elapsed_ms,
    )


@router.get(
    "/views",
    operation_id="listAskViews",
    summary="AN-016: the authorised views the assistant may read",
    response_model=AskViewsOut,
)
async def list_views(
    request: Request, actor: Annotated[User, require_roles(*ASK_ROLES)]
) -> AskViewsOut:
    client = get_client(request)
    return AskViewsOut(
        enabled=client.provider != "off",
        views=[
            AskViewOut(
                name=v.name,
                grain=v.grain,
                description=v.description,
                columns=[AskViewColumnOut(name=c, description=d) for c, d in v.columns],
            )
            for v in VIEWS
        ],
    )


__all__ = ["AskUnavailableError", "get_client", "router"]
