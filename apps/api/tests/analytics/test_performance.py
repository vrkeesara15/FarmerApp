"""WC-001 acceptance: the owner home loads in under 3 s for 50 stores.

A synthetic 50-store tenant (``tests.analytics.synthetic``: 2,000 farmers, ~36,000 orders,
15,000 visits over 60 days) is written inside the test transaction; the owner home is then
requested for the last 30 days (daily trends) and for the whole 60 days (weekly trends), each
timed end to end through the ASGI app (auth, scope, every query, serialisation).

The timed requests run with the coverage tracer paused: under ``make check`` (pytest-cov) line
tracing alone adds ~1.5 s to this request, which measured the tracer rather than the endpoint
(~1.2 s untraced, 2.9-3.3 s traced on the dev Mac). The budget is unchanged.
"""

from __future__ import annotations

import time
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import date, timedelta

import coverage
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.analytics.conftest import get
from tests.analytics.synthetic import build_synthetic
from tests.authz.conftest import Bearer

BUDGET_S = 3.0
END = date(2026, 9, 18)


@contextmanager
def _untraced() -> Iterator[None]:
    """Pause pytest-cov's tracer (if any) so the timing is the endpoint's, not the tracer's."""
    cov = coverage.Coverage.current()
    if cov is None:
        yield
        return
    cov.stop()
    try:
        yield
    finally:
        cov.start()


async def test_owner_home_under_3_seconds_for_50_stores(
    client: AsyncClient, bearer: Bearer, db_session: AsyncSession
) -> None:
    data = await build_synthetic(db_session, END)
    assert data.counts["stores"] == 50
    assert data.counts["orders"] >= 30_000

    timings: dict[str, float] = {}
    for label, days in (("30d", 30), ("60d", 60)):
        with _untraced():
            started = time.perf_counter()
            resp = await get(
                client,
                bearer,
                data.owner,
                "/owner-home",
                from_=END - timedelta(days=days - 1),
                to=END,
            )
            timings[label] = time.perf_counter() - started
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert len(body["stores"]) == 50
        assert all(s["band"] != "none" for s in body["stores"])
        revenue = next(k for k in body["kpis"] if k["key"] == "revenue")
        assert revenue["value"] > 0

    print(f"owner-home 50 stores: {timings}")  # noqa: T201  (reported in the PR)
    assert timings["30d"] < BUDGET_S, timings
    assert timings["60d"] < BUDGET_S, timings
