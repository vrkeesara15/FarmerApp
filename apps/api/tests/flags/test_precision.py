"""VA-006: precision per rule from the resolution labels, the weekly rule-quality report to
the tenant admins, auto-disable under 30 % over four weeks (audited, pending review) and the
admin re-enable (step-up, audited)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.auth.stepup import STEP_UP_HEADER, issue_step_up_token
from farmerapp.db.models.audit_log import AuditLog
from farmerapp.flags.models import Flag, FlagStatus, RuleTenantOverride
from farmerapp.flags.precision import (
    REPORT_KIND,
    label_counts,
    rule_quality,
    weekly_quality_report,
)
from farmerapp.flags.service import transition
from farmerapp.notifications.models import Notification
from farmerapp.rules.engine import run_rules
from farmerapp.rules.schema import Mode
from farmerapp.settings import get_settings
from tests.authz.conftest import Bearer
from tests.flags.conftest import RULES, make_flag
from tests.rules.harness import BaseWorld, add_user, base_world, load_fixture, seed

NOW = datetime(2026, 9, 21, 0, 0, tzinfo=UTC)  # a Monday, 05:30 IST


async def _resolve(
    session: AsyncSession,
    world: BaseWorld,
    rule_id: str,
    outcomes: list[FlagStatus],
    *,
    at: datetime,
) -> list[Flag]:
    """Raise one flag per outcome and resolve it (valid = false positive, fixed = true)."""
    auditor = world.users["auditor"]
    flags: list[Flag] = []
    for outcome in outcomes:
        flag = await make_flag(session, world, "officer", rule_id=rule_id, now=at)
        await transition(session, auditor, flag, FlagStatus.IN_REVIEW, None, now=at)
        await transition(session, auditor, flag, outcome, "checked", now=at)
        flags.append(flag)
    return flags


async def test_label_counts_and_windows(db_session: AsyncSession) -> None:
    world = await base_world(db_session)
    valid, fixed = FlagStatus.RESOLVED_VALID, FlagStatus.RESOLVED_FIXED
    await _resolve(db_session, world, "VA-F06", [valid, valid, fixed], at=NOW - timedelta(days=3))
    await _resolve(db_session, world, "VA-F06", [fixed], at=NOW - timedelta(days=20))
    await _resolve(db_session, world, "VA-F06", [valid], at=NOW - timedelta(days=40))  # too old
    week = await label_counts(db_session, world.tenant_id, since=NOW - timedelta(days=7), until=NOW)
    assert (week["VA-F06"].true_positive, week["VA-F06"].false_positive) == (1, 2)
    rows = {r.rule_id: r for r in await rule_quality(db_session, world.tenant_id, now=NOW)}
    four = rows["VA-F06"].four_weeks
    assert (four.true_positive, four.false_positive, four.resolved) == (2, 2, 4)
    assert four.precision == 0.5
    assert rows["VA-F01"].four_weeks.precision is None  # nothing resolved
    assert set(rows) == set(RULES.rules)


async def test_weekly_report_auto_disables_low_precision_rule(
    db_session: AsyncSession, client: AsyncClient, bearer: Bearer
) -> None:
    world = await base_world(db_session)
    admin = await add_user(db_session, world, "admin", UserRole.TENANT_ADMIN)
    valid, fixed = FlagStatus.RESOLVED_VALID, FlagStatus.RESOLVED_FIXED
    # VA-F06: 1 of 5 confirmed (20 %) -> disabled; VA-E05: 2 of 5 (40 %) -> stays;
    # VA-E04: 0 of 3 (under the 5-resolution minimum) -> stays.
    await _resolve(db_session, world, "VA-F06", [valid] * 4 + [fixed], at=NOW - timedelta(days=10))
    await _resolve(
        db_session, world, "VA-E05", [valid] * 3 + [fixed] * 2, at=NOW - timedelta(days=10)
    )
    await _resolve(db_session, world, "VA-E04", [valid] * 3, at=NOW - timedelta(days=10))

    report = await weekly_quality_report(db_session, world.tenant_id, now=NOW, rule_set=RULES)
    assert report.auto_disabled == ["VA-F06"]
    override = (
        await db_session.execute(
            select(RuleTenantOverride).where(RuleTenantOverride.tenant_id == world.tenant_id)
        )
    ).scalar_one()
    assert override.rule_id == "VA-F06" and override.enabled is False
    assert override.source == "auto_precision" and "20%" in override.reason
    assert float(override.precision or 0) == 0.2 and override.resolved_count == 5
    audits = (
        (
            await db_session.execute(
                select(AuditLog.action).where(
                    AuditLog.tenant_id == world.tenant_id, AuditLog.entity == "rule_tenant_override"
                )
            )
        )
        .scalars()
        .all()
    )
    assert "rule.auto_disable" in audits
    # the weekly report goes to the tenant admin (not the owner, since there is an admin)
    notes = (
        (await db_session.execute(select(Notification).where(Notification.kind == REPORT_KIND)))
        .scalars()
        .all()
    )
    assert [n.user_id for n in notes] == [admin.id]
    data = notes[0].data
    assert data["auto_disabled"] == ["VA-F06"]
    by_rule = {r["rule_id"]: r for r in data["rules"]}
    assert by_rule["VA-E05"]["four_weeks"]["precision"] == 0.4 and by_rule["VA-E05"]["enabled"]
    assert by_rule["VA-F06"]["enabled"] is False

    # the engine skips the disabled rule for this tenant
    fixture = load_fixture("VA-F06", "positive")
    await seed(db_session, world, fixture, NOW)
    run = await run_rules(
        db_session, world.tenant_id, Mode.BATCH, rule_ids=["VA-F06"], now=NOW, rule_set=RULES
    )
    assert run.skipped == ["VA-F06"] and run.rules_run == []

    # the API lists it as disabled with the reason
    listing = await client.get("/v1/flags/rules", headers=bearer(world.users["auditor"]))
    assert listing.status_code == 200, listing.text
    rows = {r["rule_id"]: r for r in listing.json()["items"]}
    assert (
        rows["VA-F06"]["enabled"] is False and "pending review" in rows["VA-F06"]["disabled_reason"]
    )
    assert listing.json()["precision_floor"] == 0.3

    # re-enable: step-up required, then audited; the precision window restarts
    url = "/v1/flags/rules/VA-F06/enable"
    body = {"reason": "Threshold raised in rules/VA-F06.yaml v2"}
    resp = await client.post(url, json=body, headers=bearer(admin))
    assert resp.status_code == 401 and resp.json()["code"] == "step_up_required"
    step_up = {STEP_UP_HEADER: issue_step_up_token(get_settings(), admin, datetime.now(UTC))}
    resp = await client.post(url, json=body, headers={**bearer(admin), **step_up})
    assert resp.status_code == 200, resp.text
    assert resp.json()["enabled"] is True and resp.json()["source"] == "admin"
    assert resp.json()["set_by"] == str(admin.id)
    again = await client.post(url, json=body, headers={**bearer(admin), **step_up})
    assert again.status_code == 409 and again.json()["code"] == "rule_not_disabled"
    unknown = await client.post(
        "/v1/flags/rules/VA-F99/enable", json=body, headers={**bearer(admin), **step_up}
    )
    assert unknown.status_code == 404
    enabled_now = await db_session.scalar(
        select(RuleTenantOverride.enabled).where(RuleTenantOverride.id == override.id)
    )
    assert enabled_now is True
    actions = (
        (
            await db_session.execute(
                select(AuditLog.action).where(AuditLog.entity == "rule_tenant_override")
            )
        )
        .scalars()
        .all()
    )
    assert "rule.enable" in actions

    # next week's report does not disable it again on the old resolutions
    later = datetime.now(UTC) + timedelta(days=7)
    second = await weekly_quality_report(db_session, world.tenant_id, now=later, rule_set=RULES)
    assert second.auto_disabled == []


async def test_owner_gets_report_without_tenant_admin(db_session: AsyncSession) -> None:
    world = await base_world(db_session)
    report = await weekly_quality_report(db_session, world.tenant_id, now=NOW, rule_set=RULES)
    assert report.notified == [world.refs["owner"]] and report.auto_disabled == []
