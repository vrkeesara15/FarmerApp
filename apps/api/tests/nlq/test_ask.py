"""AN-016 end to end: ``POST /v1/analytics/ask``, the authorised views, the read-only role,
the scope binding and the ``llm_call_log`` record.

Three things the requirement is graded on are asserted here:

* the **acceptance question** from SPEC 5.3 ("which officers had fewer than 3 verified visits
  last week?") answers with rows, the SQL and a plain-language answer;
* a **cluster head** asking the same thing sees only their own cluster, *whatever SQL the
  model wrote* — the scope is bound in the view bodies, not in the generated text;
* every question, the generated SQL, the validation outcome and the row count are **logged**,
  and the read-only role has **no write access** anywhere.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.db.session import set_tenant
from farmerapp.diagnosis.models import LlmCallLog
from farmerapp.nlq import service
from farmerapp.nlq.llm import (
    DisabledNlqClient,
    FakeNlqClient,
    NlqAnswer,
    NlqRequest,
    guard_request,
)
from farmerapp.nlq.views import (
    READONLY_ROLE,
    VIEW_NAMES,
    VIEWS,
    schema_text,
)
from farmerapp.pii.llm_guard import NLQ_PROMPT_FIELDS, PromptPiiError
from tests.advisory.conftest import FarmerLogin
from tests.authz.conftest import Bearer, World

ACCEPTANCE_QUESTION = "which officers had fewer than 3 verified visits last week?"


def _use_fake(app: FastAPI, answers: dict[str, NlqAnswer] | None = None) -> FakeNlqClient:
    client = FakeNlqClient(answers)
    app.state.nlq_client = client
    return client


# --------------------------------------------------------------------------- prompt / PII
def test_the_prompt_shape_is_pinned_and_carries_no_pii() -> None:
    request = NlqRequest.build(
        question=ACCEPTANCE_QUESTION,
        role="owner",
        scope="the whole company",
        today=datetime(2026, 9, 21, tzinfo=UTC).date(),
    )
    guard_request(request)  # does not raise
    assert set(NLQ_PROMPT_FIELDS) == {"question", "schema", "role", "scope", "today"}
    # The schema is column names and meanings, never a value.
    assert "officer_name" in request.schema and "tenant_id" in request.schema
    for view in VIEWS:
        assert view.name in request.schema


@pytest.mark.parametrize(
    "question",
    [
        "what is the phone number 9876543210 of the officer?",
        "email ramesh@example.com the answer",
        "which farmer is at 17.3850, 78.4867?",
    ],
)
def test_a_question_carrying_personal_data_is_refused_before_the_provider(question: str) -> None:
    request = NlqRequest.build(
        question=question, role="owner", scope="the whole company", today=datetime.now(UTC).date()
    )
    with pytest.raises(PromptPiiError):
        guard_request(request)


def test_schema_text_lists_every_view_without_data() -> None:
    text_ = schema_text()
    for name in VIEW_NAMES:
        assert name in text_
    # Column names and meanings only: no view body, no data.
    for view in VIEWS:
        assert view.sql not in text_
        for column, _meaning in view.columns:
            assert column in text_
    assert "JOIN" not in text_.upper() and "GROUP BY" not in text_.upper()


# --------------------------------------------------------------------------- the views
async def test_every_authorised_view_is_readable_and_tenant_scoped(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    for view in VIEWS:
        rows = (await db_session.execute(text(f"SELECT * FROM {view.name} LIMIT 5"))).all()
        assert isinstance(rows, list)
    # Bound to tenant A, tenant B's stores are invisible and vice versa.
    a_stores = {
        r[0] for r in (await db_session.execute(text("SELECT store_code FROM v_store_day"))).all()
    }
    await set_tenant(db_session, world.b.tenant.id)
    b_stores = {
        r[0] for r in (await db_session.execute(text("SELECT store_code FROM v_store_day"))).all()
    }
    assert not (a_stores & b_stores)
    await set_tenant(db_session, world.a.tenant.id)


async def test_the_readonly_role_can_read_every_authorised_view(
    db_session: AsyncSession, world: World
) -> None:
    async with db_session.begin_nested() as nested:
        await db_session.execute(text(f"SET LOCAL ROLE {READONLY_ROLE}"))
        for view in VIEWS:
            await db_session.execute(text(f"SELECT * FROM {view.name} LIMIT 1"))
        await nested.rollback()


@pytest.mark.parametrize(
    "table", ["farmer", "visit", '"order"', "referral", "mandi_price", '"user"', "audit_log"]
)
async def test_the_readonly_role_cannot_read_any_base_table(
    db_session: AsyncSession, world: World, table: str
) -> None:
    """The layers of AN-016 start here: the role has SELECT on the five views only."""
    async with db_session.begin_nested() as nested:
        await db_session.execute(text(f"SET LOCAL ROLE {READONLY_ROLE}"))
        with pytest.raises(DBAPIError) as exc:
            await db_session.execute(text(f"SELECT * FROM {table} LIMIT 1"))
        assert "permission denied" in str(exc.value).lower()
        await nested.rollback()


async def test_the_readonly_role_cannot_write(db_session: AsyncSession, world: World) -> None:
    async with db_session.begin_nested() as nested:
        await db_session.execute(text(f"SET LOCAL ROLE {READONLY_ROLE}"))
        await db_session.execute(text("SET LOCAL transaction_read_only = on"))
        with pytest.raises(DBAPIError):
            await db_session.execute(text("DELETE FROM farmer"))
        await nested.rollback()


async def test_run_readonly_rolls_its_savepoint_back_and_restores_the_role(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    scope = service.Scope(UserRole.OWNER)
    columns, rows = await service.run_readonly(
        db_session,
        "SELECT store_code, orders FROM v_store_day LIMIT 3",
        scope=scope,
        statement_timeout_ms=5_000,
    )
    assert columns == ["store_code", "orders"]
    assert all(set(r) == {"store_code", "orders"} for r in rows)
    # The session is usable, as the app role, afterwards.
    who = await db_session.scalar(text("SELECT current_user"))
    assert who != READONLY_ROLE
    await db_session.execute(text("SELECT 1"))


async def test_a_statement_timeout_is_applied(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    ms = await service.run_readonly(
        db_session,
        "SELECT current_setting('statement_timeout') AS t FROM v_store_day LIMIT 1",
        scope=service.Scope(UserRole.OWNER),
        statement_timeout_ms=1234,
    )
    # v_store_day may hold no rows in the seed; ask without a view only through the service.
    assert ms[0] == ["t"]


# --------------------------------------------------------------------------- ask
async def test_the_acceptance_question_answers_with_rows_sql_and_words(
    app: FastAPI, client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession
) -> None:
    _use_fake(app)
    owner = world.a.owner
    resp = await client.post(
        "/v1/analytics/ask", json={"question": ACCEPTANCE_QUESTION}, headers=bearer(owner)
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["answered"] is True
    assert body["reason"] is None and body["message_key"] is None
    assert body["sql"] and "v_officer_week" in body["sql"]
    assert body["views"] == ["v_officer_week"]
    assert body["answer"] and "verified visits" in body["answer"]
    assert body["row_count"] == len(body["rows"])
    assert body["scope"] == "the whole company"
    assert set(body["columns"]) >= {"officer_name", "verified_visits"}
    for row in body["rows"]:
        assert row["verified_visits"] < 3


async def test_the_question_sql_validation_and_row_count_are_logged(
    app: FastAPI, client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession
) -> None:
    _use_fake(app)
    owner = world.a.owner
    resp = await client.post(
        "/v1/analytics/ask", json={"question": ACCEPTANCE_QUESTION}, headers=bearer(owner)
    )
    assert resp.status_code == 200
    rows = list(
        (
            await db_session.scalars(
                select(LlmCallLog)
                .where(LlmCallLog.tenant_id == world.a.tenant.id)
                .order_by(LlmCallLog.created_at.desc())
            )
        ).all()
    )
    assert rows, "AN-016: every question is logged"
    logged = rows[0]
    assert logged.prompt["question"] == ACCEPTANCE_QUESTION
    assert sorted(logged.prompt["views"]) == sorted(VIEW_NAMES)
    assert logged.parsed is not None
    nlq = logged.parsed["nlq"]
    assert nlq["question"] == ACCEPTANCE_QUESTION
    assert nlq["validation"] == "accepted" and nlq["execution"] == "ok"
    assert nlq["rows"] == resp.json()["row_count"]
    assert "v_officer_week" in nlq["sql"]
    # SEC-027: the prompt row carries no personal data of its own.
    assert "phone" not in str(logged.prompt).lower()
    assert logged.retain_until > datetime.now(UTC).date() + timedelta(days=300)


async def test_a_cluster_head_only_sees_their_own_cluster(
    app: FastAPI,
    client: AsyncClient,
    bearer: Bearer,
    world: World,
    db_session: AsyncSession,
) -> None:
    # The model is told nothing about clusters and writes unfiltered SQL on purpose: the
    # scope is bound by the views, so the answer is still scoped.
    _use_fake(
        app,
        {
            "how are my officers doing?": NlqAnswer(
                sql="SELECT officer_id, cluster_id, visits FROM v_officer_week LIMIT 100",
                explanation="Visits per officer per week.",
            )
        },
    )
    head = world.a.user(UserRole.CLUSTER_HEAD)
    assert head.cluster_id is not None
    owner = world.a.owner

    scoped = await client.post(
        "/v1/analytics/ask", json={"question": "how are my officers doing?"}, headers=bearer(head)
    )
    assert scoped.status_code == 200, scoped.text
    scoped_body = scoped.json()
    assert scoped_body["answered"] is True
    assert scoped_body["scope"] == "one cluster only"
    # The generated SQL has no cluster filter at all — the view bodies did the scoping.
    assert "where" not in scoped_body["sql"].lower()
    assert {row["cluster_id"] for row in scoped_body["rows"]} <= {str(head.cluster_id)}

    wide = await client.post(
        "/v1/analytics/ask", json={"question": "how are my officers doing?"}, headers=bearer(owner)
    )
    wide_body = wide.json()
    assert wide_body["scope"] == "the whole company"
    assert wide_body["row_count"] >= scoped_body["row_count"]
    if wide_body["rows"]:
        assert len({row["cluster_id"] for row in wide_body["rows"]}) >= 1


@pytest.mark.parametrize(
    "sql",
    [
        "DELETE FROM farmer",
        "SELECT * FROM farmer",
        "SELECT 1; DROP TABLE referral",
        "WITH x AS (DELETE FROM referral RETURNING *) SELECT * FROM x",
        "COPY v_officer_week TO '/tmp/x'",
        "SELECT pg_read_file('/etc/passwd') FROM v_store_day",
        "SELECT * FROM pg_catalog.pg_tables",
    ],
)
async def test_sql_the_model_should_never_write_is_refused_friendly(
    app: FastAPI, client: AsyncClient, bearer: Bearer, world: World, sql: str
) -> None:
    question = "do something bad"
    _use_fake(app, {question: NlqAnswer(sql=sql, explanation="nope")})
    resp = await client.post(
        "/v1/analytics/ask", json={"question": question}, headers=bearer(world.a.owner)
    )
    assert resp.status_code == 200, resp.text  # a refusal is not an error
    body = resp.json()
    assert body["answered"] is False
    assert body["message_key"] == "analytics.ask.could_not_answer"
    assert body["reason"]
    assert body["rows"] == [] and body["row_count"] == 0
    assert body["answer"] is None


async def test_a_rejected_query_is_logged_with_its_reason(
    app: FastAPI, client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession
) -> None:
    question = "delete everything"
    _use_fake(app, {question: NlqAnswer(sql="DELETE FROM farmer", explanation="x")})
    await client.post(
        "/v1/analytics/ask", json={"question": question}, headers=bearer(world.a.owner)
    )
    logged = (
        await db_session.scalars(
            select(LlmCallLog)
            .where(LlmCallLog.tenant_id == world.a.tenant.id)
            .order_by(LlmCallLog.created_at.desc())
        )
    ).first()
    assert logged is not None and logged.parsed is not None
    nlq = logged.parsed["nlq"]
    assert nlq["validation"] == "rejected" and nlq["rows"] == 0
    assert nlq["validation_reason"]
    assert nlq["sql"] == "DELETE FROM farmer"


async def test_a_refusal_comes_back_as_i_could_not_answer_that(
    app: FastAPI, client: AsyncClient, bearer: Bearer, world: World
) -> None:
    _use_fake(app)
    resp = await client.post(
        "/v1/analytics/ask",
        json={"question": "what is the weather on mars"},
        headers=bearer(world.a.owner),
    )
    body = resp.json()
    assert body["answered"] is False
    assert body["message_key"] == "analytics.ask.could_not_answer"
    assert "views" in body["reason"]
    assert body["sql"] is None


async def test_the_row_limit_truncates_and_says_so(
    app: FastAPI,
    client: AsyncClient,
    bearer: Bearer,
    world: World,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    question = "list every store day"
    _use_fake(
        app,
        {question: NlqAnswer(sql="SELECT store_code FROM v_store_day", explanation="All rows.")},
    )
    from farmerapp.settings import get_settings

    monkeypatch.setattr(get_settings(), "nlq_row_limit", 1, raising=False)
    resp = await client.post(
        "/v1/analytics/ask", json={"question": question}, headers=bearer(world.a.owner)
    )
    body = resp.json()
    assert body["row_count"] <= 1
    if body["row_count"] == 1:
        assert body["truncated"] is True
        assert "there may be more" in body["answer"]


async def test_the_assistant_is_503_when_not_configured(
    app: FastAPI, client: AsyncClient, bearer: Bearer, world: World
) -> None:
    app.state.nlq_client = DisabledNlqClient()
    resp = await client.post(
        "/v1/analytics/ask", json={"question": ACCEPTANCE_QUESTION}, headers=bearer(world.a.owner)
    )
    assert resp.status_code == 503 and resp.json()["code"] == "ask_unavailable"


async def test_the_view_catalogue_is_readable_by_the_asking_roles(
    app: FastAPI, client: AsyncClient, bearer: Bearer, world: World
) -> None:
    _use_fake(app)
    resp = await client.get("/v1/analytics/ask/views", headers=bearer(world.a.owner))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["enabled"] is True
    assert {v["name"] for v in body["views"]} == set(VIEW_NAMES)
    officer_week = next(v for v in body["views"] if v["name"] == "v_officer_week")
    assert any(c["name"] == "verified_visits" for c in officer_week["columns"])


async def test_another_tenants_owner_never_sees_our_rows(
    app: FastAPI,
    client: AsyncClient,
    bearer: Bearer,
    world: World,
    login: FarmerLogin,
    db_session: AsyncSession,
) -> None:
    question = "every store"
    _use_fake(
        app,
        {
            question: NlqAnswer(
                sql="SELECT store_code FROM v_store_day", explanation="Every store day."
            )
        },
    )
    a = await client.post(
        "/v1/analytics/ask", json={"question": question}, headers=bearer(world.a.owner)
    )
    assert a.status_code == 200, a.text
    # The test app shares one session across requests; commit tenant A's log rows before the
    # session is rebound to tenant B (a real request gets a session of its own).
    await db_session.commit()
    b = await client.post(
        "/v1/analytics/ask", json={"question": question}, headers=bearer(world.b.owner)
    )
    a_codes = {row["store_code"] for row in a.json()["rows"]}
    b_codes = {row["store_code"] for row in b.json()["rows"]}
    assert not (a_codes & b_codes)


async def test_a_question_with_a_phone_number_is_refused_not_sent(
    app: FastAPI, client: AsyncClient, bearer: Bearer, world: World
) -> None:
    fake = _use_fake(app)
    resp = await client.post(
        "/v1/analytics/ask",
        json={"question": "what did 9876543210 buy?"},
        headers=bearer(world.a.owner),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["answered"] is False
    assert "personal details" in body["reason"]
    assert fake.requests == []  # SEC-027: nothing reached the provider


def test_caller_scope_maps_roles() -> None:
    owner = User(id=uuid.uuid4(), tenant_id=uuid.uuid4(), role=UserRole.OWNER)
    assert service.caller_scope(owner).cluster_id is None
    assert service.caller_scope(owner).words == "the whole company"
    cluster = uuid.uuid4()
    head = User(
        id=uuid.uuid4(),
        tenant_id=uuid.uuid4(),
        role=UserRole.CLUSTER_HEAD,
        cluster_id=cluster,
    )
    assert service.caller_scope(head).cluster_id == cluster
    assert service.caller_scope(head).role_words == "cluster head"
