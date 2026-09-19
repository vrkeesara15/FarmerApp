"""VA-004 / SEC-027: the review agent summarises a flag from its evidence bundle only, cites
only ids of the bundle, never sees PII, logs every call, and runs after the flag exists."""

from __future__ import annotations

import base64
import json
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.diagnosis.models import LlmCallLog
from farmerapp.flags.models import Flag, FlagSummary, SummaryStatus
from farmerapp.flags.review_agent import (
    SUMMARY_LABEL_KEY,
    SYSTEM_PROMPT,
    ClaudeFlagSummaryClient,
    FakeFlagSummaryClient,
    SummaryTemporaryError,
    build_bundle,
    build_client,
    handle_flag_created_message,
    mask_text,
    summarise_flag,
    summarise_pending,
    validate_answer,
)
from farmerapp.flags.service import raise_flag
from farmerapp.rules.registry import Evidence, Finding, record
from farmerapp.rules.schema import Mode, Subject
from farmerapp.settings import Settings
from farmerapp.worker.messages import PubSubMessage
from tests.authz.conftest import Bearer
from tests.diagnosis.conftest import (
    FakeAnthropic,
    FakeResponse,
    StopDetails,
    api_status_error,
    connection_error,
)
from tests.flags.conftest import RULES
from tests.rules.harness import DEFAULT_NOW, BaseWorld, base_world

OUTSIDER = "0f0f0f0f-0000-4000-8000-00000000abcd"


async def _flag(session: AsyncSession, world: BaseWorld) -> Flag:
    """A VA-F02-style flag whose title carries a name and whose metrics carry PII."""
    officer = world.refs["officer"]
    other = uuid.uuid4()
    flag = await raise_flag(
        session,
        tenant_id=world.tenant_id,
        rule=RULES.get("VA-E05"),
        finding=Finding(
            subject_type=Subject.EMPLOYEE,
            subject_id=officer,
            key=uuid.uuid4().hex,
            title="Possible duplicate of farmer Mallesh Goud",
            evidence=Evidence(
                records=[record("user", officer), record("visit", other)],
                points=[{"type": "Point", "coordinates": [79.55, 18.02]}],
                photos=["gs://b/p.jpg"],
                metrics={
                    "reason": "phone_confirms_many",
                    "farmer_name": "Mallesh Goud",
                    "phone": "+919876543210",
                    "note": "codes went to +91 98765 43210 for 3 farmers",
                    "phone_last4": "3210",
                    "farmers": 3,
                    "other_visit": str(other),
                },
            ),
        ),
        mode=Mode.BATCH,
        now=DEFAULT_NOW,
    )
    assert flag is not None
    return flag


def _answer(bundle_ids: list[str], *, lines: int = 3, extra_text: str = "") -> str:
    return json.dumps(
        {
            "summary_lines": [f"Line {i + 1} {extra_text}".strip() for i in range(lines)],
            "suggested_action": f"Open visit {bundle_ids[0]} and call the farmer.",
            "cited_record_ids": bundle_ids,
        }
    )


@pytest.fixture
async def world(db_session: AsyncSession) -> BaseWorld:
    return await base_world(db_session)


# --------------------------------------------------------------------------- the bundle
async def test_bundle_has_only_evidence_and_no_pii(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    flag = await _flag(db_session, world)
    bundle = build_bundle(flag, rule_title="Confirmation anomalies")
    text = bundle.text()
    assert "Mallesh" not in text and "Goud" not in text  # names dropped (and no flag title)
    assert "9876543210" not in text and "98765 43210" not in text
    assert "******3210" in text  # phone in free text masked to its last four digits
    assert bundle.payload["metrics"]["phone_last4"] == "3210"
    assert (
        "farmer_name" not in bundle.payload["metrics"] and "phone" not in bundle.payload["metrics"]
    )
    assert bundle.payload["map"] == {"points": 1, "polygons": 0} and bundle.payload["photos"] == 1
    assert "79.55" not in text  # no coordinates
    records = {r["id"] for r in bundle.payload["records"]}
    assert records <= bundle.allowed_ids
    assert str(flag.subject_id) in bundle.allowed_ids
    assert bundle.payload["metrics"]["other_visit"] in bundle.allowed_ids
    assert str(flag.id) not in bundle.allowed_ids  # the flag is not a record


def test_mask_text_keeps_record_ids() -> None:
    rid = "550e8400-e29b-41d4-a716-446655440000"
    assert mask_text(f"call +919876543210 about {rid}") == f"call ******3210 about {rid}"
    assert mask_text("closed 2026-09-18, 3 of 5 visits") == "closed 2026-09-18, 3 of 5 visits"


async def test_validate_answer_rules(db_session: AsyncSession, world: BaseWorld) -> None:
    bundle = build_bundle(await _flag(db_session, world), rule_title=None)
    ids = sorted(bundle.allowed_ids)
    assert validate_answer(_answer(ids[:1]), bundle).cited_record_ids == ids[:1]
    with pytest.raises(ValueError, match="not in the evidence bundle"):
        validate_answer(_answer([OUTSIDER]), bundle)
    with pytest.raises(ValueError, match="mentions ids"):
        validate_answer(_answer(ids[:1], extra_text=OUTSIDER), bundle)
    with pytest.raises(ValueError, match="schema"):
        validate_answer(_answer(ids[:1], lines=2), bundle)
    with pytest.raises(ValueError, match="schema"):
        validate_answer("not json", bundle)
    with pytest.raises(ValueError, match="schema"):
        validate_answer(json.dumps({**json.loads(_answer(ids[:1])), "extra": 1}), bundle)


# --------------------------------------------------------------------------- Claude client
async def test_claude_call_shape_and_success(db_session: AsyncSession, world: BaseWorld) -> None:
    flag = await _flag(db_session, world)
    bundle = build_bundle(flag, rule_title="Confirmation anomalies")
    ids = sorted(bundle.allowed_ids)
    fake = FakeAnthropic([FakeResponse(_answer(ids[:2]))])
    outcome = await ClaudeFlagSummaryClient(fake, model="claude-opus-5").summarise(bundle)
    assert outcome.status == SummaryStatus.DONE and outcome.answer is not None
    (call,) = fake.messages.calls
    assert call["model"] == "claude-opus-5" and call["system"] == SYSTEM_PROMPT
    assert call["output_config"]["effort"] == "low"
    fmt = call["output_config"]["format"]
    assert fmt["type"] == "json_schema"
    assert fmt["schema"]["additionalProperties"] is False
    assert set(fmt["schema"]["required"]) == {
        "summary_lines",
        "suggested_action",
        "cited_record_ids",
    }
    sent = call["messages"][0]["content"][0]["text"]
    assert "Mallesh" not in sent and "9876543210" not in sent
    assert outcome.calls[0].outcome == "ok" and outcome.calls[0].input_tokens == 1200


async def test_invalid_citation_is_rejected_and_retried_once(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    bundle = build_bundle(await _flag(db_session, world), rule_title=None)
    ids = sorted(bundle.allowed_ids)
    fake = FakeAnthropic([FakeResponse(_answer([OUTSIDER])), FakeResponse(_answer(ids[:1]))])
    outcome = await ClaudeFlagSummaryClient(fake).summarise(bundle)
    assert outcome.status == SummaryStatus.DONE
    assert [c.outcome for c in outcome.calls] == ["invalid", "ok"]
    retry_text = fake.messages.calls[1]["messages"][0]["content"][0]["text"]
    assert "previous answer was rejected" in retry_text and OUTSIDER in retry_text

    twice = FakeAnthropic([FakeResponse(_answer([OUTSIDER])), FakeResponse("{}")])
    failed = await ClaudeFlagSummaryClient(twice).summarise(bundle)
    assert failed.status == SummaryStatus.INVALID and failed.answer is None
    assert len(twice.messages.calls) == 2  # retried once, not more


async def test_refusal_gives_no_summary(db_session: AsyncSession, world: BaseWorld) -> None:
    bundle = build_bundle(await _flag(db_session, world), rule_title=None)
    fake = FakeAnthropic(
        [FakeResponse("I can't", stop_reason="refusal", stop_details=StopDetails())]
    )
    outcome = await ClaudeFlagSummaryClient(fake).summarise(bundle)
    assert outcome.status == SummaryStatus.REFUSED and outcome.answer is None
    assert outcome.calls[0].outcome == "refusal"
    assert outcome.calls[0].stop_details == {
        "type": "refusal",
        "category": "bio",
        "explanation": "declined",
    }
    cut = FakeAnthropic(
        [
            FakeResponse('{"summary', stop_reason="max_tokens"),
            FakeResponse('{"s', stop_reason="max_tokens"),
        ]
    )
    assert (await ClaudeFlagSummaryClient(cut).summarise(bundle)).status == SummaryStatus.INVALID


@pytest.mark.parametrize(
    "error",
    [lambda: api_status_error(429), lambda: api_status_error(503), connection_error],
    ids=["rate_limited", "server_error", "connection"],
)
async def test_temporary_errors_raise(db_session: AsyncSession, world: BaseWorld, error) -> None:  # type: ignore[no-untyped-def]
    bundle = build_bundle(await _flag(db_session, world), rule_title=None)
    with pytest.raises(SummaryTemporaryError) as caught:
        await ClaudeFlagSummaryClient(FakeAnthropic([error()])).summarise(bundle)
    assert len(caught.value.calls) == 1


async def test_client_error_is_final(db_session: AsyncSession, world: BaseWorld) -> None:
    bundle = build_bundle(await _flag(db_session, world), rule_title=None)
    outcome = await ClaudeFlagSummaryClient(FakeAnthropic([api_status_error(400)])).summarise(
        bundle
    )
    assert outcome.status == SummaryStatus.ERROR


def test_build_client_from_settings() -> None:
    assert build_client(Settings(flag_summary_llm="off")) is None
    assert isinstance(build_client(Settings(flag_summary_llm="fake")), FakeFlagSummaryClient)
    claude = build_client(
        Settings(flag_summary_llm="claude", flag_summary_llm_model="claude-opus-5")
    )
    assert claude is not None and claude.model == "claude-opus-5"


# --------------------------------------------------------------------------- persistence
async def test_summarise_flag_stores_summary_and_logs_calls(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    flag = await _flag(db_session, world)
    ids = sorted(build_bundle(flag, rule_title=None).allowed_ids)
    fake = FakeAnthropic([FakeResponse(_answer([OUTSIDER])), FakeResponse(_answer(ids[:1]))])
    row = await summarise_flag(db_session, flag.id, ClaudeFlagSummaryClient(fake), now=DEFAULT_NOW)
    assert row is not None and row.status == SummaryStatus.DONE.value
    assert row.summary_lines == ["Line 1", "Line 2", "Line 3"]
    assert row.cited_record_ids == ids[:1] and row.attempts == 1
    logs = (
        (await db_session.execute(select(LlmCallLog).where(LlmCallLog.flag_id == flag.id)))
        .scalars()
        .all()
    )
    assert sorted(entry.outcome for entry in logs) == ["invalid", "ok"]
    assert all(entry.diagnosis_id is None for entry in logs)
    assert all("Mallesh" not in json.dumps(entry.prompt) for entry in logs)
    assert logs[0].retain_until == (DEFAULT_NOW + timedelta(days=365)).date()
    # idempotent: a done summary is never redone
    again = await summarise_flag(db_session, flag.id, ClaudeFlagSummaryClient(FakeAnthropic([])))
    assert again is not None and again.id == row.id


async def test_temporary_error_is_logged_and_deferred(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    flag = await _flag(db_session, world)
    with pytest.raises(SummaryTemporaryError):
        await summarise_flag(
            db_session, flag.id, ClaudeFlagSummaryClient(FakeAnthropic([api_status_error(429)]))
        )
    row = (
        await db_session.execute(select(FlagSummary).where(FlagSummary.flag_id == flag.id))
    ).scalar_one()
    assert row.status == SummaryStatus.PENDING.value and row.attempts == 1
    logged = await db_session.scalar(
        select(LlmCallLog.outcome).where(LlmCallLog.flag_id == flag.id)
    )
    assert logged == "rate_limited"


def _message(body: dict[str, str]) -> PubSubMessage:
    data = base64.b64encode(json.dumps(body).encode()).decode()
    return PubSubMessage(data=data, messageId="m1")


def _provider(session: AsyncSession):  # type: ignore[no-untyped-def]
    @asynccontextmanager
    async def provide(_tenant: uuid.UUID) -> AsyncIterator[AsyncSession]:
        yield session

    return provide


async def test_sweep_and_worker_message(db_session: AsyncSession, world: BaseWorld) -> None:
    first, second = await _flag(db_session, world), await _flag(db_session, world)
    fake = FakeFlagSummaryClient()
    (report,) = await summarise_pending(
        [world.tenant_id], client=fake, session_provider=_provider(db_session), now=DEFAULT_NOW
    )
    assert report.done == 2 and {b.flag_id for b in fake.bundles} == {first.id, second.id}
    (again,) = await summarise_pending(
        [world.tenant_id], client=fake, session_provider=_provider(db_session), now=DEFAULT_NOW
    )
    assert again.done == 0 and len(fake.bundles) == 2  # nothing left to do

    third = await _flag(db_session, world)
    message = _message({"tenant_id": str(world.tenant_id), "flag_id": str(third.id)})
    done = await handle_flag_created_message(
        message, client=fake, session_provider=_provider(db_session)
    )
    assert done is not None and done.done == 1
    bad = _message({"tenant_id": "nope"})
    assert await handle_flag_created_message(bad, client=fake) is None


# --------------------------------------------------------------------------- the API
async def test_detail_shows_summary_to_reviewers_only(
    client: AsyncClient, bearer: Bearer, db_session: AsyncSession, world: BaseWorld
) -> None:
    flag = await _flag(db_session, world)
    await summarise_flag(db_session, flag.id, FakeFlagSummaryClient(), now=DEFAULT_NOW)
    resp = await client.get(f"/v1/flags/{flag.id}", headers=bearer(world.users["cluster_head"]))
    assert resp.status_code == 200, resp.text
    summary = resp.json()["automated_summary"]
    assert summary["label_key"] == SUMMARY_LABEL_KEY and summary["status"] == "done"
    assert len(summary["summary_lines"]) == 3 and summary["cited_record_ids"]
    own = await client.get(f"/v1/flags/{flag.id}", headers=bearer(world.users["officer"]))
    assert own.status_code == 200 and own.json()["automated_summary"] is None
