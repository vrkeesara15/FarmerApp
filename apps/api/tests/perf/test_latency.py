"""NF-005 API latency suite: p95 < 300 ms for reads, < 600 ms for writes.

Not part of the default run (``tests/conftest.py`` ignores ``tests/perf`` unless
``FARMERAPP_PERF=1``). ``make perf-api`` runs it on one xdist worker, so it gets a database of
its own (cloned from the migrated template, dropped afterwards) and may commit.

1. Seeds the pilot-sized demo data with the real seed job (``FULL`` profile, committed):
   tenant ``fcc`` with 5 stores, 200 farmers, 5 officers, a week of duty, visits (~216),
   orders, payments and stock; then the nightly rule batch so the flag inbox is not empty.
2. Drives the real app (every request its own session / transaction, as in production)
   through ``httpx.ASGITransport`` with ``CONCURRENCY`` requests in flight.
3. Per endpoint: ``WARMUP`` unmeasured calls, then ``SAMPLES`` measured ones; p50 / p95 of
   the wall time of each call. Writes a Markdown table to ``PERF_REPORT`` (default
   ``perf-report.md``) and fails when a p95 is over its budget.

In-process numbers (no TLS, load balancer or Cloud SQL network hop) on a laptop: they catch
N+1 queries, missing indexes and slow code; production numbers need a Cloud Run load test.
"""

from __future__ import annotations

import asyncio
import os
import platform
import random
import statistics
import time
import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient, Response
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import create_async_engine

from farmerapp.api.app import create_app
from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User, UserRole
from farmerapp.db.session import get_engine, get_session_factory, tenant_scope
from farmerapp.farmers.models import Farm, Farmer
from farmerapp.jobs import seed as seed_mod
from farmerapp.rules.jobs import run_rules_job
from farmerapp.settings import get_settings
from tests.authz.conftest import World, _load_tenant
from tests.conftest import TEST_MIGRATION_DATABASE_URL
from tests.orders.helpers import order_body

pytestmark = pytest.mark.perf

READ_BUDGET_MS = 300.0
WRITE_BUDGET_MS = 600.0
#: Requests in flight at once, all in this one Python process (like one Cloud Run instance):
#: the pilot's 5 officers syncing plus console users.
CONCURRENCY = int(os.environ.get("PERF_CONCURRENCY", "4"))
SAMPLES = int(os.environ.get("PERF_SAMPLES", "80"))
WARMUP = 8
#: A device syncs its outbox every 15 minutes (``sampling.upload_s``): ~20 ops. A day offline
#: gives 50+ (the server takes up to 200): measured and reported, gated per op (see below).
SYNC_OPS = 20
SYNC_OPS_BACKLOG = 50
#: The backlog batch is judged per op against the write budget spread over a typical batch:
#: 50 ops within 50 / 20 x 600 ms = 1500 ms (docs/perf/NF-005.md, "Sync batches").
BACKLOG_BUDGET_MS = WRITE_BUDGET_MS * SYNC_OPS_BACKLOG / SYNC_OPS


@dataclass
class Result:
    name: str
    kind: str  # read | write
    samples: list[float]
    statuses: set[int]
    budget_ms: float | None = None

    def pct(self, q: float) -> float:
        ordered = sorted(self.samples)
        return ordered[min(len(ordered) - 1, round(q * (len(ordered) - 1)))]

    @property
    def budget(self) -> float:
        if self.budget_ms is not None:
            return self.budget_ms
        return READ_BUDGET_MS if self.kind == "read" else WRITE_BUDGET_MS


Call = Callable[[AsyncClient, int], Awaitable[Response]]


async def _measure(
    client: AsyncClient, name: str, kind: str, call: Call, *, samples: int = SAMPLES
) -> Result:
    for i in range(WARMUP):
        await call(client, -1 - i)
    gate = asyncio.Semaphore(CONCURRENCY)
    times: list[float] = []
    statuses: set[int] = set()

    async def one(i: int) -> None:
        async with gate:
            start = time.perf_counter()
            resp = await call(client, i)
            times.append((time.perf_counter() - start) * 1000)
            statuses.add(resp.status_code)

    await asyncio.gather(*(one(i) for i in range(samples)))
    return Result(name, kind, times, statuses)


def _report(results: list[Result], elapsed_s: float) -> str:
    lines = [
        "| Endpoint | Kind | n | p50 ms | p95 ms | budget ms | status |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in results:
        verdict = "ok" if r.pct(0.95) <= r.budget else "OVER"
        lines.append(
            f"| {r.name} | {r.kind} | {len(r.samples)} | {statistics.median(r.samples):.0f} | "
            f"{r.pct(0.95):.0f} | {r.budget:.0f} | {verdict} |"
        )
    machine = (
        f"{platform.system()} {platform.release()} {platform.machine()}, "
        f"{os.cpu_count()} CPUs, Python {platform.python_version()}"
    )
    return (
        f"NF-005 latency suite, {datetime.now(UTC):%Y-%m-%d %H:%M} UTC, concurrency "
        f"{CONCURRENCY}, {SAMPLES} samples per endpoint, {elapsed_s:.0f} s total.\n"
        f"Machine: {machine}.\n\n" + "\n".join(lines) + "\n"
    )


async def _world() -> World:
    factory = get_session_factory()
    async with factory() as session, session.begin():
        a = await _load_tenant(session, "fcc")
        b = await _load_tenant(session, "gfl")
    return World(a=a, b=b)


async def _officer_farms(officer: User) -> list[tuple[uuid.UUID, uuid.UUID, float, float]]:
    """(farmer, farm, lat, lon) of every farm of the officer's farmers."""
    factory = get_session_factory()
    async with factory() as session, session.begin(), tenant_scope(session, officer.tenant_id):
        rows = await session.execute(
            select(Farmer.id, Farm.id, Farm.centroid_lat, Farm.centroid_lon)
            .join(Farm, Farm.farmer_id == Farmer.id)
            .where(Farmer.registered_by == officer.id, Farm.deleted_at.is_(None))
            .order_by(Farmer.id, Farm.id)
        )
        return [(f, farm, float(lat or 0), float(lon or 0)) for f, farm, lat, lon in rows.tuples()]


async def _officer_villages(officer: User) -> list[uuid.UUID]:
    factory = get_session_factory()
    async with factory() as session, session.begin(), tenant_scope(session, officer.tenant_id):
        rows = await session.execute(
            select(Farmer.village_id).where(Farmer.registered_by == officer.id).distinct()
        )
        return sorted(rows.scalars())


_SYLLABLES = ("ra", "ma", "su", "ve", "ko", "la", "ni", "sri", "ga", "pa", "ta", "ya", "de", "bu")


def _name(rng: random.Random) -> str:
    """Distinct synthetic names (similar names in one village would trip VA-F02 on purpose)."""

    def word(n: int) -> str:
        return "".join(rng.choice(_SYLLABLES) for _ in range(n)).capitalize()

    return f"{word(rng.randint(2, 4))} {word(rng.randint(2, 3))}"


async def test_nf005_api_latency(app_engine: Any) -> None:
    started = time.perf_counter()
    # The app under test uses its own engine / sessions on this worker's database.
    get_engine.cache_clear()
    get_session_factory.cache_clear()
    await seed_mod.run_seed(seed_mod.FULL)
    world = await _world()
    fcc = world.a.tenant.id
    await run_rules_job([fcc])  # nightly batch: a realistic flag inbox
    # Production tables have planner statistics (autovacuum); a freshly loaded database does
    # not until autovacuum gets to it, and the sync change-feed plan then degrades from
    # ~50 ms to seconds (docs/perf/NF-005.md). Analyse as the owner, like autovacuum would.
    owner = create_async_engine(TEST_MIGRATION_DATABASE_URL, isolation_level="AUTOCOMMIT")
    try:
        async with owner.connect() as conn:
            await conn.execute(text("ANALYZE"))
    finally:
        await owner.dispose()

    app: FastAPI = create_app()
    auth: AuthServices = app.state.auth

    def as_(user: User) -> dict[str, str]:
        token = auth.tokens.issue_access_token(user, auth.clock.now())
        return {"Authorization": f"Bearer {token}", "X-Device-Id": f"perf-{user.id}"}

    owner_user = world.a.owner
    officer = world.a.user(UserRole.FIELD_OFFICER)
    manager = world.a.user(UserRole.STORE_MANAGER)
    head = world.a.user(UserRole.CLUSTER_HEAD)
    farms = await _officer_farms(officer)
    assert len(farms) >= 20, "the FULL seed gives every officer ~40 farmers"
    officers = [u for u in world.a.everyone if u.role == UserRole.FIELD_OFFICER]
    farmers_of = {o.id: sorted({f for f, *_ in await _officer_farms(o)}) for o in officers}
    villages_of = {o.id: await _officer_villages(o) for o in officers}
    rng = random.Random(5)  # nosec B311 - synthetic names, not security
    store = world.a.store_id
    results: list[Result] = []

    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://perf") as client:

        def get(path: str, user: User, **params: Any) -> Call:
            async def call(c: AsyncClient, _i: int) -> Response:
                return await c.get(path, params=params, headers=as_(user))

            return call

        reads = [
            ("GET /v1/me", get("/v1/me", officer)),
            ("GET /v1/farmers (officer)", get("/v1/farmers", officer, limit=50)),
            ("GET /v1/farmers (owner)", get("/v1/farmers", owner_user, limit=50)),
            ("GET /v1/visits (cluster head)", get("/v1/visits", head, limit=50)),
            ("GET /v1/visits (owner)", get("/v1/visits", owner_user, limit=50)),
            ("GET /v1/analytics/owner-home", get("/v1/analytics/owner-home", owner_user)),
            ("GET /v1/flags (owner)", get("/v1/flags", owner_user, limit=50)),
            ("GET /v1/catalog/products", get("/v1/catalog/products", manager, store_id=store)),
        ]
        for name, call in reads:
            result = await _measure(client, name, "read", call)
            assert result.statuses == {200}, (name, result.statuses)
            results.append(result)

        # Stock for the order writes (not measured).
        receipt = await client.post(
            f"/v1/stores/{store}/stock/receipts",
            json={
                "reference": "PERF",
                "lines": [
                    {
                        "sku_id": str(world.a.sku_id),
                        "batch_no": f"PERF-{uuid.uuid4().hex[:6]}",
                        "expiry": "2030-01-01",
                        "qty": "100000",
                        "cost_paise": 1000,
                    }
                ],
            },
            headers=as_(manager),
        )
        assert receipt.status_code == 201, receipt.text

        serial = iter(range(1, 10**6))

        def sync_batch(size: int) -> Call:
            return lambda c, i: _sync(c, i, size)

        async def _sync(c: AsyncClient, i: int, size: int) -> Response:
            """Registrations and edits of the officer's own farmers, 4 : 1 (the heaviest ops:
            registrations run the VA-F01 / F02 / F03 / F06 rules). Batches in flight at the
            same time come from different officers (or different farmers of one officer), as
            they do in the field."""
            edits = size // 5
            who = officers[i % len(officers)]
            mine = farmers_of[who.id]
            start = ((i // len(officers)) * edits) % max(1, len(mine) - edits)
            now = datetime.now(UTC).isoformat()
            ops: list[dict[str, Any]] = [
                {
                    "op_id": str(uuid.uuid4()),
                    "entity": "farmer",
                    "action": "update",
                    "entity_id": str(farmer_id),
                    "base_version": 1,
                    "payload": {"landmark": f"Perf landmark {i}.{n}"},
                    "client_ts": now,
                }
                for n, farmer_id in enumerate(mine[start : start + edits])
            ]
            while len(ops) < size:
                k = next(serial)
                ops.append(
                    {
                        "op_id": str(uuid.uuid4()),
                        "entity": "farmer",
                        "action": "create",
                        "entity_id": str(uuid.uuid4()),
                        "base_version": 0,
                        "payload": {
                            "phone": f"+9197{k:08d}",
                            "name": _name(rng),
                            "village_id": str(rng.choice(villages_of[who.id])),
                            "language": "te",
                            "farms": [],
                            "consents": [{"purpose": "data", "granted": True}],
                        },
                        "client_ts": now,
                    }
                )
            resp = await c.post(
                "/v1/sync",
                json={"device_id": f"perf-{who.id}", "cursor": cursors[who.id], "ops": ops},
                headers=as_(who),
            )
            if resp.status_code == 200:
                cursors[who.id] = resp.json()["cursor"]  # incremental, as the device does
            return resp

        # Each device made its first full pull before (not measured): it syncs incrementally.
        cursors: dict[uuid.UUID, str | None] = {}
        for who in officers:
            first = await client.post(
                "/v1/sync",
                json={"device_id": f"perf-{who.id}", "cursor": None, "ops": []},
                headers=as_(who),
            )
            assert first.status_code == 200, first.text
            cursors[who.id] = first.json()["cursor"]

        async def check_in(c: AsyncClient, i: int) -> Response:
            farmer_id, farm_id, lat, lon = farms[i % len(farms)]
            return await c.post(
                "/v1/visits/check-in",
                json={
                    "farmer_id": str(farmer_id),
                    "farm_id": str(farm_id),
                    "purpose": "advisory",
                    "checkin_at": datetime.now(UTC).isoformat(),
                    "checkin_point": {"lat": lat, "lon": lon, "accuracy_m": 8.0},
                    "device_integrity": {"is_mock": False, "is_rooted": False, "clock_drift_s": 2},
                },
                headers=as_(officer),
            )

        async def order(c: AsyncClient, _i: int) -> Response:
            return await c.post("/v1/orders", json=order_body(world), headers=as_(officer))

        writes: list[tuple[str, Call, int, float | None]] = [
            (f"POST /v1/sync ({SYNC_OPS} ops)", sync_batch(SYNC_OPS), SAMPLES // 2, None),
            (
                f"POST /v1/sync ({SYNC_OPS_BACKLOG} ops, backlog)",
                sync_batch(SYNC_OPS_BACKLOG),
                max(20, SAMPLES // 4),
                BACKLOG_BUDGET_MS,
            ),
            ("POST /v1/visits/check-in", check_in, SAMPLES, None),
            ("POST /v1/orders", order, SAMPLES, None),
        ]
        for name, call, n, budget in writes:
            result = await _measure(client, name, "write", call, samples=n)
            assert result.statuses <= {200, 201}, (name, result.statuses)
            result.budget_ms = budget
            results.append(result)

        # Payments: one open order each (placed outside the measurement).
        orders: list[str] = []
        for _ in range(SAMPLES + WARMUP):
            placed = await order(client, 0)
            orders.append(placed.json()["id"])

        async def payment(c: AsyncClient, i: int) -> Response:
            order_id = orders[i if i >= 0 else SAMPLES - 1 - i]
            return await c.post(
                "/v1/payments",
                json={"order_id": order_id, "mode": "card_terminal", "reference_note": "RRN"},
                headers=as_(manager),
            )

        paid = await _measure(client, "POST /v1/payments (card)", "write", payment)
        assert paid.statuses == {201}, paid.statuses
        results.append(paid)

    report = _report(results, time.perf_counter() - started)
    target = Path(os.environ.get("PERF_REPORT", "perf-report.md"))
    await asyncio.to_thread(target.write_text, report)
    print(report)  # noqa: T201  (make perf-api shows it)
    over = [f"{r.name}: p95 {r.pct(0.95):.0f} ms" for r in results if r.pct(0.95) > r.budget]
    assert not over, "NF-005 budget exceeded: " + "; ".join(over)
    assert get_settings().app_env == "test"
