"""``FlagCountsPort``: the owner home and the scorecard read open flags only through it (the
flags branch registers the real adapter on ``app.state.flag_counts``)."""

from __future__ import annotations

import uuid
from dataclasses import replace
from datetime import UTC, datetime

from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.ports import (
    NULL_FLAG_COUNTS,
    FlagCounts,
    FlagQuery,
    FlagSummary,
)
from tests.analytics.builders import Mini
from tests.analytics.conftest import get
from tests.analytics.test_owner_home import FROM, TO
from tests.authz.conftest import Bearer


class FakeFlags:
    def __init__(self, officer: uuid.UUID) -> None:
        self.officer = officer
        self.queries: list[FlagQuery] = []

    async def counts(self, session: AsyncSession, query: FlagQuery) -> FlagCounts:
        self.queries.append(query)
        return FlagCounts(open_total=4, open_high=1, by_officer={self.officer: 3})

    async def open_totals(
        self, session: AsyncSession, query: FlagQuery, instants: list[datetime]
    ) -> list[int]:
        self.queries.extend(replace(query, opened_before=at) for at in instants)
        return [4 for _ in instants]

    async def open_high_severity(
        self, session: AsyncSession, query: FlagQuery, limit: int
    ) -> list[FlagSummary]:
        return [
            FlagSummary(
                id=uuid.UUID(int=1),
                rule="VA-E02",
                severity="high",
                title="impossible_travel",
                opened_at=datetime(2026, 8, 5, 6, tzinfo=UTC),
                officer_id=self.officer,
            )
        ]


async def test_owner_home_and_scorecard_read_flags_through_the_port(
    app: FastAPI, client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    fake = FakeFlags(mini.user("o1").id)
    app.state.flag_counts = fake
    head = mini.user("cluster_head")
    body = (await get(client, bearer, head, "/owner-home", from_=FROM, to=TO)).json()
    flags = next(k for k in body["kpis"] if k["key"] == "open_flags")
    assert flags["value"] == 4 and flags["last_year"] == 4
    assert [p["value"] for p in flags["trend"]] == [4] * 10
    assert body["high_severity_flags"][0]["rule"] == "VA-E02"
    assert "open_flags" not in body["notes"]
    # The port is asked for the caller's scope: the northern stores and officers only.
    assert fake.queries[0].tenant_id == mini.tid
    assert set(fake.queries[0].store_ids or ()) == {mini.stores["N1"].id, mini.stores["N2"].id}
    assert set(fake.queries[0].officer_ids or ()) == {mini.user("o1").id}

    team = (await get(client, bearer, head, "/field-team", from_=FROM, to=TO)).json()
    assert team["items"][0]["flags"] == 3


async def test_null_adapter_answers_zeros(db_session: AsyncSession) -> None:
    query = FlagQuery(tenant_id=uuid.uuid4())
    assert await NULL_FLAG_COUNTS.counts(db_session, query) == FlagCounts()
    assert await NULL_FLAG_COUNTS.open_high_severity(db_session, query, 5) == []
