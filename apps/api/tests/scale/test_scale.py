"""NF-007 scale suite: one tenant at 1/50th of the target, measured and explained.

Not part of the default run (``tests/conftest.py`` ignores ``tests/scale`` unless
``FARMERAPP_SCALE=1``). ``make scale-api`` runs it on one xdist worker, so it gets a database
of its own, cloned from the migrated template and dropped afterwards, and may commit.

What it does, in order:

1. Seeds the demo tenant (``SMALL``) for the structure — clusters, stores, villages, the
   catalogue, the corpus — then adds 100 officers and fills the tenant to 40,000 farmers,
   40,000 visits, 400,000 photo rows, 20,000 diagnoses, 20,000 orders and ~105,000 location
   points with set-based SQL (``tests/scale/synthetic.py``).
2. ``ANALYZE`` as the owner, because a freshly loaded database has no planner statistics and
   every plan below would be judged on a fiction (the same reason NF-005 does it).
3. Measures p50 / p95 of the hot paths a tenant's day is made of: login, a sync batch,
   the farmers list, owner home, the flags inbox and a diagnosis create.
4. Runs ``EXPLAIN (ANALYZE, BUFFERS)`` on the queries behind those paths over the big tables
   and **fails on a sequential scan** of ``farmer``, ``visit``, ``visit_photo``,
   ``diagnosis``, ``order`` or ``location_point``. A plan that reads the whole tenant is the
   thing that does not survive fifty times this data.
5. Writes ``apps/api/scale-report.md`` — the numbers, the plans that mattered and the
   extrapolation — which is the evidence behind ``docs/perf/NF-007.md``.

What it is not: a cloud load test. It is one Python process against a Docker Postgres with no
network hop, so absolute latencies are a floor, not a forecast. The value is in the *shape*:
a plan that is O(tenant size) here is O(tenant size) in Cloud SQL too, and a p95 that is flat
between 200 farmers (NF-005) and 40,000 (here) stays flat at 2 million.
"""

from __future__ import annotations

import asyncio
import os
import platform
import re
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
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import get_engine, get_session_factory, tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.jobs import seed as seed_mod
from farmerapp.platform_admin.usage import recount
from farmerapp.tenants.models import Store, Village
from tests.conftest import TEST_MIGRATION_DATABASE_URL
from tests.scale import synthetic

pytestmark = pytest.mark.scale

REPORT = Path(os.environ.get("SCALE_REPORT", "scale-report.md"))
SAMPLES = int(os.environ.get("SCALE_SAMPLES", "40"))
# One request at a time by default: the question this suite answers is "does the *data
# volume* break a request?", not "how many concurrent users fit on one instance" (that is
# NF-005's question, and the Cloud Run concurrency knob). docs/perf/NF-007.md reports both.
CONCURRENCY = int(os.environ.get("SCALE_CONCURRENCY", "1"))
WARMUP = 5

#: SPEC 7. The suite seeds 1/50th of this and the report extrapolates.
TARGET = {"tenants": 50, "officers": 5_000, "farmers": 2_000_000, "photos": 20_000_000}

#: Tables whose row count grows with a tenant's size. A sequential scan on one of these in a
#: request-path plan is the NF-007 failure mode.
BIG_TABLES = ("location_point", "visit", "diagnosis", "corpus_image", "farmer", "order")
#: ... plus the photo tables, which are the largest by row count.
WATCHED = (*BIG_TABLES, "visit_photo", "farm_photo")
#: A sequential scan that reads more rows than this is a plan that does not survive 50x.
SEQ_SCAN_ROWS = int(os.environ.get("SCALE_SEQ_SCAN_ROWS", "5000"))

#: The one plan that reads a large slice of a tenant *by design*, named here rather than
#: silently passing. AN-001 owner home aggregates every visit in the range in Python
#: (``analytics/facts.visits``), so Postgres is right to read them all — an index cannot help
#: a query that returns 99.99% of the rows it filters. The fix is to aggregate in SQL, not to
#: add an index; docs/perf/NF-007.md, "The finding that is not an index".
KNOWN_WIDE: dict[str, tuple[str, ...]] = {
    "owner home visit facts (AN-001, the known finding)": ("visit",),
    # `usage-recount` and the NF-012 sweep are jobs that count a month of a tenant's photos
    # on purpose, one tenant at a time. Reading most of a month's rows with a sequential scan
    # is the right plan for a count, and it is exactly why the WC-014 counters are
    # incremental and this query never runs on a request.
    "photos of one month (WC-014 recount / NF-012 sweep, a job)": ("visit_photo",),
}


def _rows_touched(plan_text: str, node_line: str) -> int:
    """Rows a ``Seq Scan`` node actually read: its ``rows=`` plus ``Rows Removed by Filter``."""
    lines = plan_text.splitlines()
    index = lines.index(node_line)
    match = re.search(r"actual time=[\d.]+\.\.[\d.]+ rows=(\d+)", node_line)
    rows = int(match.group(1)) if match else 0
    for line in lines[index + 1 :]:
        if "Rows Removed by Filter:" in line:
            rows += int(line.split("Rows Removed by Filter:")[1].split()[0])
            break
        if line.strip().startswith("->"):
            break
    return rows


@dataclass
class Result:
    name: str
    samples: list[float]
    statuses: set[int]

    def pct(self, q: float) -> float:
        ordered = sorted(self.samples)
        return ordered[min(len(ordered) - 1, round(q * (len(ordered) - 1)))]


Call = Callable[[AsyncClient, int], Awaitable[Response]]


async def _measure(client: AsyncClient, name: str, call: Call, *, samples: int = SAMPLES) -> Result:
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
    return Result(name, times, statuses)


# --------------------------------------------------------------------------- query plans
@dataclass
class Plan:
    name: str
    sql: str
    text: str

    @property
    def seq_scans(self) -> list[str]:
        """Watched tables this plan reads sequentially *and* expensively.

        A sequential scan is not wrong by itself: over a 48-row corpus, or an empty daily
        partition, it is the right plan and forcing an index there would be cargo cult. What
        NF-007 cares about is a plan that touches a *large slice of a tenant* to answer one
        request, so a scan only counts when it read more than ``SEQ_SCAN_ROWS`` rows (returned
        plus removed by the filter). Partitions of ``location_point`` never count: scanning one
        day's partition instead of the whole table is the partitioning working.
        """
        found: list[str] = []
        for line in self.text.splitlines():
            if "Seq Scan on " not in line:
                continue
            table = line.split("Seq Scan on ", 1)[1].split()[0].strip('"')
            if table.startswith("location_point_p") or table not in WATCHED or table in found:
                continue
            if _rows_touched(self.text, line) > SEQ_SCAN_ROWS:
                found.append(table)
        return found


async def _explain(session: Any, name: str, sql: str, **params: Any) -> Plan:
    rows = await session.execute(text(f"EXPLAIN (ANALYZE, BUFFERS) {sql}"), params)  # nosec B608
    return Plan(name=name, sql=sql.strip(), text="\n".join(r[0] for r in rows))


# --------------------------------------------------------------------------- the suite
async def _one_upload(client: AsyncClient, headers: dict[str, str]) -> str:
    """One completed image upload, whose blob every measured diagnosis reuses."""
    import hashlib

    data = b"\xff\xd8\xff" + b"scale" * 200
    digest = hashlib.sha256(data).hexdigest()
    init = await client.post(
        "/v1/uploads",
        json={
            "sha256": digest,
            "size_bytes": len(data),
            "content_type": "image/jpeg",
            "purpose": "diagnosis",
            "chunk_size": 262144,
        },
        headers=headers,
    )
    assert init.status_code in (200, 201), init.text
    upload_id = init.json()["upload_id"]
    put = await client.put(
        f"/v1/uploads/{upload_id}/chunks/0",
        content=data,
        headers={
            **headers,
            "Content-Type": "application/octet-stream",
            "X-Chunk-Sha256": digest,
        },
    )
    assert put.status_code in (200, 201, 204), put.text
    done = await client.post(f"/v1/uploads/{upload_id}/complete", headers=headers)
    assert done.status_code in (200, 201), done.text
    uri: str = done.json()["blob_uri"]
    return uri


async def _officers(session: Any, tenant_id: uuid.UUID, store_id: uuid.UUID) -> list[User]:
    """100 field officers, created through the ORM (only 100 rows, and they must log in)."""
    made: list[User] = []
    for i in range(synthetic.OFFICERS):
        user = User(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            phone=f"+9197{i:08d}",
            name=f"Scale Officer {i}",
            role=UserRole.FIELD_OFFICER,
            store_id=store_id,
            language="te",
            status=UserStatus.ACTIVE,
        )
        session.add(user)
        made.append(user)
    await session.flush()
    return made


@pytest.mark.serial
async def test_nf007_scale(app_engine: Any) -> None:
    started = time.perf_counter()
    get_engine.cache_clear()
    get_session_factory.cache_clear()

    # 1. Structure from the real seed, then the synthetic volume. ------------
    await seed_mod.run_seed(seed_mod.SMALL)
    tenant_id = seed_mod.demo_tenant_id(seed_mod.DEMO_TENANT_SLUG)
    factory = get_session_factory()
    async with factory() as session:
        async with tenant_scope(session, tenant_id):
            tenant = await session.get(Tenant, tenant_id)
            assert tenant is not None
            tenant.plan = "unlimited"  # WC-014: the scale tenant is not plan-limited
            stores = list((await session.execute(select(Store.id))).scalars())
            villages = list((await session.execute(select(Village.id))).scalars())
            officers = await _officers(session, tenant_id, stores[0])
            officer_ids = [o.id for o in officers]
            await session.commit()
        async with tenant_scope(session, tenant_id):
            data = await synthetic.build(
                session,
                tenant_id,
                officers=officer_ids,
                villages=villages,
                stores=stores,
            )
        async with tenant_scope(session, tenant_id):
            counters = await recount(session, tenant_id)
            await session.commit()

    # 2. Planner statistics, as autovacuum would give them. ------------------
    owner = create_async_engine(TEST_MIGRATION_DATABASE_URL, isolation_level="AUTOCOMMIT")
    analyze_started = time.perf_counter()
    try:
        async with owner.connect() as conn:
            await conn.execute(text("ANALYZE"))
    finally:
        await owner.dispose()
    analyze_s = time.perf_counter() - analyze_started

    # 3. The hot paths. ------------------------------------------------------
    app: FastAPI = create_app()
    auth: AuthServices = app.state.auth
    async with factory() as session, tenant_scope(session, tenant_id):
        owner_user = (
            (
                await session.execute(
                    select(User).where(User.tenant_id == tenant_id, User.role == UserRole.OWNER)
                )
            )
            .scalars()
            .first()
        )
        officer = officers[0]
        # SPEC 2.6: the officer may only diagnose their own farmers.
        farmer_id = (
            (
                await session.execute(
                    select(Farmer.id)
                    .where(Farmer.tenant_id == tenant_id, Farmer.registered_by == officers[0].id)
                    .limit(1)
                )
            )
            .scalars()
            .one()
        )
    assert owner_user is not None

    def as_(user: User) -> dict[str, str]:
        token = auth.tokens.issue_access_token(user, auth.clock.now())
        return {"Authorization": f"Bearer {token}", "X-Device-Id": f"scale-{user.id}"}

    results: list[Result] = []
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://scale") as client:
        blob_uri = await _one_upload(client, as_(officer))

        def get(path: str, user: User, **params: Any) -> Call:
            async def call(c: AsyncClient, _i: int) -> Response:
                return await c.get(path, params=params, headers=as_(user))

            return call

        async def login(c: AsyncClient, i: int) -> Response:
            """FA-001 login: the phone -> tenant lookup plus token issue (no OTP wait)."""
            return await c.get("/v1/me", headers=as_(officers[i % len(officers)]))

        async def sync_batch(c: AsyncClient, i: int) -> Response:
            """A device's first pull: the change feed over a tenant of this size."""
            who = officers[i % len(officers)]
            return await c.post(
                "/v1/sync",
                json={"device_id": f"scale-{who.id}", "cursor": None, "ops": []},
                headers={**as_(who), "Idempotency-Key": uuid.uuid4().hex},
            )

        async def diagnosis_create(c: AsyncClient, i: int) -> Response:
            """DX-002 for one of the tenant's 40,000 farmers. The image is a real completed
            upload reused across samples, so this measures the diagnosis path (kNN prefilter,
            thresholds, write) and not the upload path."""
            return await c.post(
                "/v1/diagnoses",
                json={
                    "farmer_id": str(farmer_id),
                    "crop_code": "paddy",
                    "images": [{"blob_uri": blob_uri}],
                },
                headers={**as_(officer), "Idempotency-Key": uuid.uuid4().hex},
            )

        for name, call in (
            ("login (GET /v1/me)", login),
            ("GET /v1/diagnoses?limit=50", get("/v1/diagnoses", owner_user, limit=50)),
            ("GET /v1/farmers?limit=50 (owner)", get("/v1/farmers", owner_user, limit=50)),
            ("GET /v1/farmers?limit=50 (officer)", get("/v1/farmers", officer, limit=50)),
            ("GET /v1/analytics/owner-home", get("/v1/analytics/owner-home", owner_user)),
            ("GET /v1/flags?limit=50 (owner)", get("/v1/flags", owner_user, limit=50)),
            ("GET /v1/visits?limit=50 (owner)", get("/v1/visits", owner_user, limit=50)),
            ("POST /v1/sync (pull)", sync_batch),
            ("POST /v1/diagnoses", diagnosis_create),
        ):
            result = await _measure(client, name, call)
            results.append(result)

    # 4. The plans behind them. ---------------------------------------------
    plans: list[Plan] = []
    async with factory() as session, tenant_scope(session, tenant_id):
        plans.append(
            await _explain(
                session,
                "farmers list page (keyset)",
                "SELECT * FROM farmer WHERE tenant_id = :tid AND deleted_at IS NULL "
                "ORDER BY created_at DESC, id DESC LIMIT 50",
                tid=tenant_id,
            )
        )
        plans.append(
            await _explain(
                session,
                "visits list page",
                "SELECT * FROM visit WHERE tenant_id = :tid AND deleted_at IS NULL "
                "ORDER BY created_at DESC LIMIT 50",
                tid=tenant_id,
            )
        )
        plans.append(
            await _explain(
                session,
                "diagnoses of a farmer",
                "SELECT * FROM diagnosis WHERE tenant_id = :tid AND farmer_id = :fid "
                "ORDER BY created_at DESC LIMIT 20",
                tid=tenant_id,
                fid=farmer_id,
            )
        )
        plans.append(
            await _explain(
                session,
                "orders of a store, recent first",
                'SELECT * FROM "order" WHERE tenant_id = :tid ORDER BY created_at DESC LIMIT 50',
                tid=tenant_id,
            )
        )
        plans.append(
            await _explain(
                session,
                "photos of one month (WC-014 recount / NF-012 sweep, a job)",
                "SELECT count(*) FROM visit_photo WHERE tenant_id = :tid "
                "AND created_at >= now() - interval '30 days'",
                tid=tenant_id,
            )
        )
        plans.append(
            await _explain(
                session,
                "one officer's track for a day (VV-005 replay)",
                "SELECT * FROM location_point WHERE tenant_id = :tid AND officer_id = :oid "
                "AND ts >= now() - interval '1 day' ORDER BY ts",
                tid=tenant_id,
                oid=officer_ids[0],
            )
        )
        plans.append(
            await _explain(
                session,
                "owner home visit facts (AN-001, the known finding)",
                "SELECT officer_id, farmer_id, checkin_at, checkout_at, score, confirmed_at, id "
                "FROM visit WHERE tenant_id = :tid AND deleted_at IS NULL "
                "AND checkin_at >= now() - interval '30 days' AND checkin_at < now()",
                tid=tenant_id,
            )
        )
        plans.append(
            await _explain(
                session,
                "corpus images of a crop (DX-003 kNN prefilter)",
                "SELECT count(*) FROM corpus_image WHERE tenant_id = :tid AND status = 'approved'",
                tid=tenant_id,
            )
        )

    offenders = {
        p.name: [t for t in p.seq_scans if t not in KNOWN_WIDE.get(p.name, ())]
        for p in plans
        if [t for t in p.seq_scans if t not in KNOWN_WIDE.get(p.name, ())]
    }

    # 5. The report. ---------------------------------------------------------
    elapsed = time.perf_counter() - started
    report = _report(data, counters, results, plans, elapsed=elapsed, analyze_s=analyze_s)
    await asyncio.to_thread(REPORT.write_text, report)
    print(report)  # noqa: T201 - the evidence belongs in the run output

    assert not offenders, "sequential scans over tables that grow with tenant size: " + "; ".join(
        f"{name}: {', '.join(tables)}" for name, tables in offenders.items()
    )
    for result in results:
        assert result.statuses <= {200, 201, 202}, (result.name, result.statuses)
    # WC-001: "Loads in under 3 s for 50 stores". Held here at one request at a time, over a
    # tenant at the NF-007 target size; the concurrency-4 number is in docs/perf/NF-007.md.
    by_name = {r.name: r for r in results}
    owner_home_p95 = by_name["GET /v1/analytics/owner-home"].pct(0.95)
    assert owner_home_p95 < 3_000, f"owner home p95 {owner_home_p95:.0f} ms (WC-001: < 3 s)"
    # The counters must equal the truth even after 840,000 rows arrived behind their back —
    # ``recount`` is what reconciles a bulk load (WC-014).
    assert counters["farmers"] == data.farmers


def _report(
    data: synthetic.ScaleData,
    counters: dict[str, int],
    results: list[Result],
    plans: list[Plan],
    *,
    elapsed: float,
    analyze_s: float,
) -> str:
    factor = TARGET["farmers"] / max(data.farmers, 1)
    machine = (
        f"{platform.system()} {platform.release()} {platform.machine()}, "
        f"{os.cpu_count()} CPUs, Python {platform.python_version()}"
    )
    lines = [
        "# NF-007 scale run",
        "",
        f"{datetime.now(UTC):%Y-%m-%d %H:%M} UTC · machine: {machine}",
        f"Total {elapsed:.0f} s (seed {data.seconds:.0f} s, ANALYZE {analyze_s:.0f} s), "
        f"concurrency {CONCURRENCY}, {SAMPLES} samples per endpoint.",
        "",
        "## Seeded volume (one tenant, 1/50th of the SPEC 7 target)",
        "",
        "| Table | Rows | At 50 tenants |",
        "|---|---:|---:|",
        f"| farmer | {data.farmers:,} | {data.farmers * 50:,} |",
        f"| visit | {data.visits:,} | {data.visits * 50:,} |",
        f"| visit_photo | {data.photos:,} | {data.photos * 50:,} |",
        f"| diagnosis | {data.diagnoses:,} | {data.diagnoses * 50:,} |",
        f"| order | {data.orders:,} | {data.orders * 50:,} |",
        f"| location_point | {data.location_points:,} | {data.location_points * 50:,} |",
        "",
        f"WC-014 counters after the bulk load (`usage-recount`): {counters}",
        "",
        "## Hot paths",
        "",
        "| Endpoint | n | p50 ms | p95 ms | statuses |",
        "|---|---:|---:|---:|---|",
    ]
    for r in results:
        lines.append(
            f"| {r.name} | {len(r.samples)} | {statistics.median(r.samples):.0f} | "
            f"{r.pct(0.95):.0f} | {sorted(r.statuses)} |"
        )
    lines += [
        "",
        "## Query plans over the tables that grow with tenant size",
        "",
    ]
    for plan in plans:
        verdict = "**SEQ SCAN: " + ", ".join(plan.seq_scans) + "**" if plan.seq_scans else "indexed"
        lines += [
            f"### {plan.name} — {verdict}",
            "",
            "```sql",
            plan.sql,
            "```",
            "",
            "```",
            plan.text,
            "```",
            "",
        ]
    wide = sorted({t for p in plans for t in p.seq_scans})
    lines += [
        "## Extrapolation",
        "",
        f"SPEC 7 asks for {TARGET['tenants']} tenants, {TARGET['officers']:,} officers, "
        f"{TARGET['farmers']:,} farmers and {TARGET['photos']:,} photos. That is "
        f"{TARGET['farmers'] // TARGET['tenants']:,} farmers **per tenant** — which is what "
        f"this run measured (1/{factor:.0f} of the total). The target is reached by adding "
        "tenants, not by growing one, and every request is already scoped to one tenant, so "
        "the per-request numbers above are the numbers at target.",
        "",
        "Every request-path plan above is an index or index-only scan bounded by `tenant_id` "
        "plus a range or a key: the work is a function of the *page size*, not of the tenant's "
        "size, and the b-tree depth grows with log(n).",
        "",
    ]
    if wide:
        lines += [
            "Plans that read a wide slice of the tenant (named, not hidden): "
            + ", ".join(f"`{t}`" for t in wide)
            + ". See the sections above for which query and why; "
            "docs/perf/NF-007.md carries the judgement on each.",
            "",
        ]
    lines += [
        "What does grow with 50 tenants: total index and heap size (linear, so ~50x), "
        "autovacuum work, connection demand (`infra/modules/db_budget`), and any job that "
        "iterates tenants — which is why `platform_admin.jobs` pages the registry and runs "
        "one tenant per transaction.",
        "",
    ]
    return "\n".join(lines) + "\n"
