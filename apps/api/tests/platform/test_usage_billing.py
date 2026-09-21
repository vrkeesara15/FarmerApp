"""WC-014 usage endpoint, recount and the monthly billing statement."""

from __future__ import annotations

import csv
import io
import uuid
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.platform_admin import billing
from farmerapp.platform_admin.models import PLATFORM_TENANT_ID
from farmerapp.platform_admin.plans import Metric, plan_by_name
from farmerapp.platform_admin.state import invalidate
from farmerapp.platform_admin.usage import current, month_bounds, month_key, record, recount
from tests.platform.conftest import TENANT_BODY


async def _created(client: AsyncClient, headers: dict[str, str]) -> uuid.UUID:
    resp = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=headers)
    assert resp.status_code == 201, resp.text
    return uuid.UUID(resp.json()["tenant"]["id"])


async def test_usage_endpoint_reports_every_metric_against_its_limit(
    client: AsyncClient, as_platform: dict[str, str]
) -> None:
    tenant_id = await _created(client, as_platform)
    resp = await client.get(f"/v1/admin/tenants/{tenant_id}/usage", headers=as_platform)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["plan"] == "pilot"
    by_metric = {m["metric"]: m for m in body["metrics"]}
    assert set(by_metric) == {m.value for m in Metric}
    pilot = plan_by_name("pilot").limits
    assert by_metric["farmers"]["limit"] == pilot.farmers
    assert by_metric["farmers"]["used"] == 0
    assert by_metric["farmers"]["remaining"] == pilot.farmers
    assert by_metric["stores"]["used"] == 1  # the placeholder store
    # Monthly metrics carry their period; head counts carry ``total``.
    assert by_metric["photos"]["period"] == month_key()
    assert by_metric["stores"]["period"] == "total"


async def test_recount_agrees_with_the_incremental_counters(
    client: AsyncClient,
    db_session: AsyncSession,
    as_platform: dict[str, str],
    bearer: Any,
    step_up: Any,
) -> None:
    """The point of the counters is that they equal a ``count(*)`` without doing one."""
    tenant_id = await _created(client, as_platform)
    async with tenant_scope(db_session, tenant_id):
        admin = (
            (await db_session.execute(select(User).where(User.tenant_id == tenant_id)))
            .scalars()
            .one()
        )
    await set_tenant(db_session, tenant_id)
    headers = {**bearer(admin), **step_up(admin)}
    for i in range(3):
        resp = await client.post(
            "/v1/users",
            json={"phone": f"+91900017730{i}", "name": f"Officer {i}", "role": "field_officer"},
            headers=headers,
        )
        assert resp.status_code == 201, resp.text

    async with tenant_scope(db_session, tenant_id):
        incremental = await current(db_session, tenant_id, Metric.OFFICERS)
        counted = await recount(db_session, tenant_id, metrics=(Metric.OFFICERS,))
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    assert incremental == 3
    assert counted["officers"] == 3


async def test_recount_backfills_a_tenant_that_predates_the_counters(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    tenant_id = await _created(client, as_platform)
    async with tenant_scope(db_session, tenant_id):
        # A user written without going through the API (as the seed does).
        db_session.add(
            User(
                id=uuid.uuid4(),
                tenant_id=tenant_id,
                phone="+919000177401",
                name="Legacy officer",
                role=UserRole.FIELD_OFFICER,
                language="en",
                status=UserStatus.ACTIVE,
            )
        )
        await db_session.flush()
        assert await current(db_session, tenant_id, Metric.OFFICERS) == 0  # drifted
        await recount(db_session, tenant_id, metrics=(Metric.OFFICERS,))
        assert await current(db_session, tenant_id, Metric.OFFICERS) == 1  # fixed
    await set_tenant(db_session, PLATFORM_TENANT_ID)


async def test_statement_prices_the_overage_and_freezes_it(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    tenant_id = await _created(client, as_platform)
    async with tenant_scope(db_session, tenant_id):
        await record(db_session, tenant_id, Metric.FARMERS, 5_010)  # 10 over the pilot limit
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    invalidate(tenant_id)

    resp = await client.post(
        f"/v1/admin/tenants/{tenant_id}/statements", json={}, headers=as_platform
    )
    assert resp.status_code == 201, resp.text
    statement = resp.json()
    plan = plan_by_name("pilot")
    lines = {line["metric"]: line for line in statement["lines"]}
    assert lines["farmers"]["used"] == 5_010
    assert lines["farmers"]["included"] == plan.limits.farmers
    assert lines["farmers"]["overage"] == 10
    assert lines["farmers"]["amount_paise"] == 10 * plan.overage_paise["farmers"]
    assert statement["base_price_paise"] == plan.base_price_paise
    assert statement["overage_paise"] == 10 * plan.overage_paise["farmers"]
    assert statement["total_paise"] == statement["base_price_paise"] + statement["overage_paise"]
    assert statement["external_invoice_ref"] is None  # nothing is charged

    # Frozen: more farmers afterwards do not change the stored statement.
    async with tenant_scope(db_session, tenant_id):
        await record(db_session, tenant_id, Metric.FARMERS, 100)
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    listed = await client.get(f"/v1/admin/tenants/{tenant_id}/statements", headers=as_platform)
    assert listed.json()["items"][0]["lines"][0]["used"] == statement["lines"][0]["used"]


async def test_statement_csv_has_a_row_per_metric_plus_base_and_total(
    client: AsyncClient, as_platform: dict[str, str]
) -> None:
    tenant_id = await _created(client, as_platform)
    period = month_key()
    await client.post(
        f"/v1/admin/tenants/{tenant_id}/statements",
        json={"period": period},
        headers=as_platform,
    )
    resp = await client.get(
        f"/v1/admin/tenants/{tenant_id}/statements/{period}/csv", headers=as_platform
    )
    assert resp.status_code == 200, resp.text
    assert resp.headers["content-type"].startswith("text/csv")
    assert "nava" in resp.headers["content-disposition"]
    rows = list(csv.DictReader(io.StringIO(resp.text)))
    assert [r["metric"] for r in rows][-2:] == ["base", "total"]
    assert {r["metric"] for r in rows} >= {m.value for m in Metric}
    assert all(r["tenant_slug"] == "nava" for r in rows)


async def test_statement_csv_404s_for_a_period_never_generated(
    client: AsyncClient, as_platform: dict[str, str]
) -> None:
    tenant_id = await _created(client, as_platform)
    resp = await client.get(
        f"/v1/admin/tenants/{tenant_id}/statements/2020-01/csv", headers=as_platform
    )
    assert resp.status_code == 404


async def test_regenerating_a_period_replaces_the_row(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    tenant_id = await _created(client, as_platform)
    period = month_key()
    first = await client.post(
        f"/v1/admin/tenants/{tenant_id}/statements",
        json={"period": period},
        headers=as_platform,
    )
    async with tenant_scope(db_session, tenant_id):
        await record(db_session, tenant_id, Metric.FARMERS, 6_000)
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    second = await client.post(
        f"/v1/admin/tenants/{tenant_id}/statements",
        json={"period": period},
        headers=as_platform,
    )
    assert second.json()["total_paise"] > first.json()["total_paise"]
    listed = await client.get(f"/v1/admin/tenants/{tenant_id}/statements", headers=as_platform)
    assert len(listed.json()["items"]) == 1  # replaced, not appended


async def test_payment_port_is_unconfigured_and_says_so() -> None:
    port = billing.UnconfiguredBillingPort()
    with pytest.raises(NotImplementedError, match="No platform payment provider"):
        await port.charge(None, tenant_slug="nava")  # type: ignore[arg-type]


def test_month_bounds_wrap_the_year() -> None:
    start, end = month_bounds("2026-12")
    assert start == datetime(2026, 12, 1, tzinfo=UTC)
    assert end == datetime(2027, 1, 1, tzinfo=UTC)


async def test_plan_change_takes_effect_on_the_limits(
    client: AsyncClient, as_platform: dict[str, str]
) -> None:
    tenant_id = await _created(client, as_platform)
    resp = await client.patch(
        f"/v1/admin/tenants/{tenant_id}",
        json={"plan": "growth", "plan_limits": {"farmers": 80_000}},
        headers=as_platform,
    )
    assert resp.status_code == 200, resp.text
    usage = await client.get(f"/v1/admin/tenants/{tenant_id}/usage", headers=as_platform)
    by_metric = {m["metric"]: m for m in usage.json()["metrics"]}
    assert usage.json()["plan"] == "growth"
    assert by_metric["farmers"]["limit"] == 80_000
    assert by_metric["officers"]["limit"] == plan_by_name("growth").limits.officers
