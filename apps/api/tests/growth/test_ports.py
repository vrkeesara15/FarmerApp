"""M7 growth ports and wiring: the ``EmailSender`` adapters, settings, jobs on the CLI."""

from __future__ import annotations

import contextlib
import json
import uuid
from collections.abc import AsyncIterator
from datetime import date
from typing import Any

import httpx
import pytest
from sqlalchemy.ext.asyncio import AsyncSession
from typer.testing import CliRunner

from farmerapp.exports.email import (
    Attachment,
    Email,
    EmailError,
    FakeEmailSender,
    HttpEmailSender,
    LogEmailSender,
    build_email_sender,
)
from farmerapp.jobs.cli import cli
from farmerapp.settings import Settings
from farmerapp.tenants.settings import TenantSettings, tenant_settings

MESSAGE = Email(
    to=("a@example.com", "b@example.com"),
    subject="Weekly",
    text="Attached.",
    attachments=(Attachment("r.pdf", b"%PDF", "application/pdf"),),
)


async def test_http_email_sender_posts_the_message() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(202)

    settings = Settings(email_provider="sendgrid", email_api_key="test-key")
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    await HttpEmailSender(settings, client).send(MESSAGE)
    [request] = seen
    assert request.headers["authorization"] == "Bearer test-key"
    body = json.loads(request.content)
    assert [t["email"] for t in body["personalizations"][0]["to"]] == [
        "a@example.com",
        "b@example.com",
    ]
    assert body["attachments"][0]["filename"] == "r.pdf"


async def test_http_email_sender_errors() -> None:
    failing = httpx.AsyncClient(transport=httpx.MockTransport(lambda _r: httpx.Response(500)))
    with pytest.raises(EmailError):
        await HttpEmailSender(Settings(email_api_key="k"), failing).send(MESSAGE)
    with pytest.raises(EmailError, match="EMAIL_API_KEY"):
        await HttpEmailSender(Settings(email_api_key=None)).send(MESSAGE)


async def test_email_sender_selection_and_fakes() -> None:
    assert isinstance(build_email_sender(Settings(email_provider="log")), LogEmailSender)
    assert isinstance(build_email_sender(Settings(email_provider="fake")), FakeEmailSender)
    assert isinstance(build_email_sender(Settings(email_provider="sendgrid")), HttpEmailSender)
    await LogEmailSender().send(MESSAGE)  # logs, sends nothing
    fake = FakeEmailSender(fail=True)
    with pytest.raises(EmailError):
        await fake.send(MESSAGE)


def test_growth_settings_defaults_and_validation() -> None:
    s = TenantSettings()
    assert s.campaigns.attribution_days == 14 and s.campaigns.holdout_pct == 0
    assert s.stock_alerts.expiry_days == [60, 30] and s.stock_alerts.default_reorder_level == 10
    assert s.reports.weekly_owner_emails == [] and s.accounting.cash_ledger == "Cash"
    with pytest.raises(ValueError):
        tenant_settings({"reports": {"weekly_owner_emails": ["not-an-email"]}})
    with pytest.raises(ValueError):
        tenant_settings({"campaigns": {"holdout_pct": 80}})


def test_growth_jobs_are_on_the_cli() -> None:
    out = CliRunner().invoke(cli, ["--help"]).output
    for command in (
        "send-campaigns",
        "close-incentives",
        "stock-alerts",
        "accounting-export",
        "run-report-schedules",
        "weekly-owner-report",
    ):
        assert command in out, command


async def test_job_wrappers_bind_each_tenant(
    tmp_path: Any, monkeypatch: pytest.MonkeyPatch, db_session: AsyncSession
) -> None:
    """The wrappers open one job session per tenant under the system actor; here the job
    session is the test's session (the module-level engine points at the dev database)."""
    from farmerapp.auth.providers import FakeProvider
    from farmerapp.campaigns import jobs as campaign_jobs
    from farmerapp.campaigns.service import CampaignSender
    from farmerapp.db.session import tenant_scope
    from farmerapp.exports import jobs as export_jobs
    from farmerapp.incentives import jobs as incentive_jobs
    from farmerapp.incentives.service import NoActiveRulesError
    from farmerapp.stock import alerts
    from farmerapp.uploads.blobstore import LocalBlobStore

    @contextlib.asynccontextmanager
    async def session_for(tenant_id: uuid.UUID) -> AsyncIterator[AsyncSession]:
        async with tenant_scope(db_session, tenant_id):
            yield db_session

    for module in (campaign_jobs, export_jobs, incentive_jobs, alerts):
        monkeypatch.setattr(module, "job_session", session_for)
    tenant = uuid.uuid4()
    store, email = LocalBlobStore(tmp_path), FakeEmailSender()
    fake = FakeProvider()
    [(sent, changed)] = await campaign_jobs.run_send_campaigns(
        [tenant], sender=CampaignSender(sms=fake, whatsapp=fake)
    )
    assert (sent.tenant_id, sent.campaigns, changed) == (tenant, 0, 0)
    [stock] = await alerts.run_stock_alerts([tenant])
    assert stock.notifications == 0
    [schedules] = await export_jobs.run_report_schedules([tenant], store=store, email=email)
    assert schedules.ran == []
    [books] = await export_jobs.run_accounting_export([tenant], store=store, email=email)
    assert books.stores == []
    [weekly] = await export_jobs.run_weekly_owner_report([tenant], store=store, email=email)
    assert weekly.status == "no_viewer" and email.sent == []
    with pytest.raises(NoActiveRulesError):
        await incentive_jobs.run_close_incentives([tenant], month=date(2026, 8, 1))


def test_growth_commands_print_their_reports(monkeypatch: pytest.MonkeyPatch) -> None:
    from farmerapp.campaigns import jobs as campaign_jobs
    from farmerapp.campaigns.service import SendReport
    from farmerapp.exports import jobs as export_jobs
    from farmerapp.exports.owner_weekly import WeeklyResult
    from farmerapp.exports.service import ScheduleReport
    from farmerapp.incentives import jobs as incentive_jobs
    from farmerapp.incentives.service import CloseReport
    from farmerapp.stock import alerts
    from farmerapp.stock.alerts import StockAlertReport

    tenant = uuid.uuid4()

    async def sends(ids: Any, **_: Any) -> Any:
        return [(SendReport(tenant_id=ids[0], campaigns=1, sent=3), 2)]

    async def close(ids: Any, **_: Any) -> Any:
        return [CloseReport(tenant_id=ids[0], month=date(2026, 8, 1), total_paise=5)]

    async def stock(ids: Any, **_: Any) -> Any:
        return [StockAlertReport(tenant_id=ids[0], day=date(2026, 9, 20), notifications=4)]

    async def books(ids: Any, **_: Any) -> Any:
        return [export_jobs.AccountingReport(tenant_id=ids[0], day=date(2026, 9, 18))]

    async def schedules(ids: Any, **_: Any) -> Any:
        return [ScheduleReport(tenant_id=ids[0])]

    async def weekly(ids: Any, **_: Any) -> Any:
        return [WeeklyResult(ids[0], date(2026, 9, 14), "sent")]

    monkeypatch.setattr(campaign_jobs, "run_send_campaigns", sends)
    monkeypatch.setattr(incentive_jobs, "run_close_incentives", close)
    monkeypatch.setattr(alerts, "run_stock_alerts", stock)
    monkeypatch.setattr(export_jobs, "run_accounting_export", books)
    monkeypatch.setattr(export_jobs, "run_report_schedules", schedules)
    monkeypatch.setattr(export_jobs, "run_weekly_owner_report", weekly)
    runner = CliRunner()
    t = str(tenant)
    cases = {
        ("send-campaigns", "--tenant-id", t): "sent=3",
        ("close-incentives", "--tenant-id", t, "--month", "2026-08-01"): "total_paise=5",
        ("stock-alerts", "--tenant-id", t): "notifications=4",
        ("accounting-export", "--tenant-id", t, "--date", "2026-09-18"): "date=2026-09-18",
        ("run-report-schedules", "--tenant-id", t): "ran=0",
        ("weekly-owner-report", "--tenant-id", t): "week=2026-09-14 sent",
    }
    for args, expected in cases.items():
        result = runner.invoke(cli, list(args))
        assert result.exit_code == 0, result.output
        assert expected in result.output, (args, result.output)
