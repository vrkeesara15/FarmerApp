"""M6 fixtures: the SMALL world (its seeded paddy corpus), photos in the blob store, a
scriptable LLM and a fake Anthropic client that records every request."""

from __future__ import annotations

import hashlib
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

import anthropic
import httpx2
import pytest
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.diagnosis.encoder import FakeEncoder
from farmerapp.diagnosis.llm import (
    FakeLlmDiagnosisClient,
    LlmDiagnosisClient,
    LlmOutcome,
    LlmRequest,
)
from farmerapp.diagnosis.models import CorpusProblem
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.farmers.models import Farmer
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import Bearer, World, bearer, step_up  # noqa: F401
from tests.authz.conftest import world as world  # fixture re-exported

PhotoPutter = Callable[..., Any]


@pytest.fixture
def blobs(app: FastAPI) -> BlobStore:
    store: BlobStore = app.state.blobs
    return store


async def put_photo(blobs: BlobStore, tenant_id: uuid.UUID, data: bytes) -> str:
    sha = hashlib.sha256(data).hexdigest()
    return await blobs.put(f"{tenant_id}/diagnosis/{sha}", data, content_type="image/jpeg")


@dataclass
class ScriptedLlm:
    """``LlmDiagnosisClient`` whose outcome a test sets (``script``), recording requests."""

    provider: str = "scripted"
    model: str = "scripted-llm"
    script: Callable[[LlmRequest], LlmOutcome] | None = None
    requests: list[LlmRequest] = field(default_factory=list)
    error: Exception | None = None

    async def diagnose(self, request: LlmRequest) -> LlmOutcome:
        self.requests.append(request)
        if self.error is not None:
            raise self.error
        if self.script is None:
            return await FakeLlmDiagnosisClient().diagnose(request)
        return self.script(request)


@pytest.fixture
def llm() -> ScriptedLlm:
    return ScriptedLlm()


@pytest.fixture
def services(app: FastAPI, llm: ScriptedLlm) -> DiagnosisServices:
    """The app's diagnosis services with a scriptable LLM (inline delivery)."""
    current: DiagnosisServices = app.state.diagnosis
    svc = DiagnosisServices(
        settings=current.settings,
        encoder=FakeEncoder(),
        llm=llm,
        blobs=current.blobs,
        publisher=None,
    )
    app.state.diagnosis = svc
    return svc


def use_llm(app: FastAPI, client: LlmDiagnosisClient) -> None:
    app.state.diagnosis.llm = client


@dataclass(frozen=True)
class Paddy:
    crop: Crop
    problems: dict[str, CorpusProblem]  # pest code -> corpus problem
    farmer: Farmer  # the demo farmer (has the farmer login)
    farmer_user: User
    officer: User  # the officer who registered ``farmer``
    agronomist: User


async def load_paddy(session: AsyncSession, world: World) -> Paddy:
    from farmerapp.catalog.models import PestOrDisease

    tid = world.a.tenant.id
    crop = (
        await session.execute(select(Crop).where(Crop.tenant_id == tid, Crop.code == "paddy"))
    ).scalar_one()
    rows = (
        await session.execute(
            select(CorpusProblem, PestOrDisease.code)
            .join(PestOrDisease, PestOrDisease.id == CorpusProblem.pest_or_disease_id)
            .where(CorpusProblem.tenant_id == tid, CorpusProblem.crop_id == crop.id)
        )
    ).all()
    problems = {str(code): problem for problem, code in rows}
    farmer_user = world.a.user(UserRole.FARMER)
    farmer = (
        await session.execute(select(Farmer).where(Farmer.user_id == farmer_user.id))
    ).scalar_one()
    officer = next(u for u in world.a.everyone if u.id == farmer.registered_by)
    return Paddy(
        crop=crop,
        problems=problems,
        farmer=farmer,
        farmer_user=farmer_user,
        officer=officer,
        agronomist=world.a.user(UserRole.AGRONOMIST),
    )


@pytest.fixture
async def paddy(db_session: AsyncSession, world: World) -> Paddy:
    return await load_paddy(db_session, world)


# --------------------------------------------------------------------------- fake Anthropic
@dataclass
class FakeMessages:
    responses: list[Any]
    calls: list[dict[str, Any]] = field(default_factory=list)

    async def create(self, **kwargs: Any) -> Any:
        self.calls.append(kwargs)
        item = self.responses.pop(0)
        if isinstance(item, BaseException):
            raise item
        return item


@dataclass
class FakeAnthropic:
    """Stands in for ``anthropic.AsyncAnthropic``: ``messages.create`` returns / raises the
    scripted items in order and records the keyword arguments of every call."""

    responses: list[Any]
    messages: FakeMessages = field(init=False)

    def __post_init__(self) -> None:
        self.messages = FakeMessages(self.responses)


@dataclass
class Block:
    type: str
    text: str = ""


@dataclass
class Usage:
    input_tokens: int = 1200
    output_tokens: int = 80


@dataclass
class StopDetails:
    type: str = "refusal"
    category: str | None = "bio"
    explanation: str | None = "declined"

    def model_dump(self, mode: str = "json") -> dict[str, Any]:
        return {"type": self.type, "category": self.category, "explanation": self.explanation}


@dataclass
class FakeResponse:
    text: str
    stop_reason: str = "end_turn"
    stop_details: StopDetails | None = None
    usage: Usage = field(default_factory=Usage)
    thinking_first: bool = True

    @property
    def content(self) -> list[Block]:
        blocks = [Block("text", self.text)]
        return [Block("thinking"), *blocks] if self.thinking_first else blocks


def _request() -> httpx2.Request:
    """The anthropic SDK (1.x) is built on httpx2; its errors carry httpx2 objects."""
    return httpx2.Request("POST", "https://api.anthropic.com/v1/messages")


def api_status_error(status: int) -> anthropic.APIStatusError:
    response = httpx2.Response(status, request=_request(), json={"error": {"message": "x"}})
    if status == 429:
        return anthropic.RateLimitError("rate limited", response=response, body=None)
    if status >= 500:
        return anthropic.InternalServerError("server error", response=response, body=None)
    return anthropic.BadRequestError("bad request", response=response, body=None)


def connection_error() -> anthropic.APIConnectionError:
    return anthropic.APIConnectionError(request=_request())
