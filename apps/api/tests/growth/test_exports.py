"""WC-013 exports and scheduled reports, NF-013 consent export: list scope and filters reused,
step-up and audit, CSV / XLSX into the exports bucket with a signed URL, cron in IST and
emailed schedules through the ``EmailSender`` port."""

from __future__ import annotations

import csv
import io
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.models import AuditLog
from farmerapp.exports import cron
from farmerapp.exports.email import FakeEmailSender, HttpEmailSender
from farmerapp.exports.models import ExportJob, ReportRun, ReportSchedule
from farmerapp.exports.service import run_due_schedules
from farmerapp.exports.writers import read_xlsx_rows, write_csv, write_xlsx
from farmerapp.settings import get_settings
from tests.analytics.builders import Mini
from tests.authz.conftest import Bearer
from tests.growth.conftest import T0, consented_world, headers

IST = cron.IST


# --------------------------------------------------------------------------- cron
def test_cron_monday_0800_ist() -> None:
    sunday = datetime(2026, 9, 20, 10, 0, tzinfo=IST)
    fire = cron.next_fire(cron.WEEKLY_MONDAY_0800, sunday)
    assert fire == datetime(2026, 9, 21, 2, 30, tzinfo=UTC)  # Monday 08:00 IST
    assert fire.astimezone(IST).isoweekday() == 1 and fire.astimezone(IST).hour == 8
    # Exactly at the fire time: the next one is a week later.
    assert cron.next_fire("0 8 * * 1", fire) == fire + timedelta(days=7)
    assert cron.next_fire("*/15 * * * *", datetime(2026, 9, 20, 10, 7, tzinfo=IST)) == datetime(
        2026, 9, 20, 10, 15, tzinfo=IST
    )
    # Day of month OR day of week when both are restricted (Vixie cron).
    first_or_friday = cron.next_fire("0 9 1 * 5", datetime(2026, 9, 20, tzinfo=IST))
    assert first_or_friday == datetime(2026, 9, 25, 9, tzinfo=IST)  # a Friday before 1 Oct
    assert cron.next_fire("30 2 * * 7", datetime(2026, 9, 20, 3, tzinfo=IST)).astimezone(
        IST
    ) == datetime(2026, 9, 27, 2, 30, tzinfo=IST)  # 7 = Sunday
    for bad in ("0 8 * *", "61 8 * * 1", "0 8 31 2 *", "a b c d e", "*/0 * * * *"):
        with pytest.raises(cron.CronError):
            cron.validate(bad)


# --------------------------------------------------------------------------- writers
def test_csv_and_xlsx_writers() -> None:
    rows: list[list[Any]] = [["=HYPERLINK(1)", -5, "రైతు"], [None, 1.5, "plain"]]
    out, count = write_csv(("a", "b", "c"), rows)
    text = out.read().decode("utf-8-sig")
    assert count == 2
    parsed = list(csv.reader(io.StringIO(text)))
    assert parsed[0] == ["a", "b", "c"]
    assert parsed[1] == ["'=HYPERLINK(1)", "-5", "రైతు"]  # formula neutralised, number kept
    xlsx, n = write_xlsx(("a", "b", "c"), rows, sheet="Farmers")
    assert n == 2
    assert read_xlsx_rows(xlsx.read()) == [
        ["a", "b", "c"],
        ["=HYPERLINK(1)", "-5", "రైతు"],  # an inline string, never a formula
        ["", "1.5", "plain"],
    ]


def test_http_email_payload_has_attachments() -> None:
    from farmerapp.exports.email import Attachment, Email

    sender = HttpEmailSender(get_settings())
    payload = sender.payload(
        Email(to=("a@example.com",), subject="S", text="T",
              attachments=(Attachment("r.csv", b"x,y", "text/csv"),))
    )  # fmt: skip
    assert payload["personalizations"] == [{"to": [{"email": "a@example.com"}]}]
    assert payload["attachments"][0]["filename"] == "r.csv"  # type: ignore[index]


# --------------------------------------------------------------------------- API
async def _download(app: FastAPI, job_id: str, session: AsyncSession) -> bytes:
    job = await session.get(ExportJob, uuid.UUID(job_id))
    assert job is not None and job.blob_uri
    return bytes(await app.state.exports.get(job.blob_uri))


async def test_export_orders_uses_the_list_scope_needs_step_up_and_is_audited(
    app: FastAPI,
    client: AsyncClient,
    mini: Mini,
    bearer: Bearer,
    step_up: Bearer,
    db_session: AsyncSession,
) -> None:
    await mini.sale("N1", "f1", T0, [("own", 2, 1000)])
    await mini.sale("S1", "f3", T0, [("multi", 1, 800)])
    manager = mini.user("store_manager")  # store N1
    body = {"resource": "orders", "format": "csv", "filters": {"from": "2026-01-01T00:00:00Z"}}
    no_step = await client.post("/v1/exports", json=body, headers=headers(bearer, manager))
    assert no_step.status_code == 401 and no_step.json()["code"] == "step_up_required"
    resp = await client.post("/v1/exports", json=body, headers=headers(bearer, manager, step_up))
    assert resp.status_code == 201, resp.text
    out = resp.json()
    assert out["rows"] == 1 and out["url"] and out["url_expires_at"]
    assert out["filters"] == {"from": "2026-01-01T00:00:00Z"}
    data = (await _download(app, out["id"], db_session)).decode("utf-8-sig")
    table = list(csv.DictReader(io.StringIO(data)))
    assert [r["store_id"] for r in table] == [str(mini.stores["N1"].id)]
    assert table[0]["total_paise"] == "2000"
    trail = (
        await db_session.execute(select(AuditLog).where(AuditLog.action == "export.create"))
    ).scalar_one()
    assert trail.actor_id == manager.id and trail.after is not None
    assert trail.after["resource"] == "orders" and trail.after["rows"] == 1
    listed = await client.get("/v1/exports", headers=headers(bearer, manager))
    assert [j["id"] for j in listed.json()["items"]] == [out["id"]]
    assert listed.json()["items"][0]["url"] is None
    fresh = await client.get(f"/v1/exports/{out['id']}", headers=headers(bearer, manager))
    assert fresh.status_code == 200 and fresh.json()["url"]
    other = await client.get(
        f"/v1/exports/{out['id']}", headers=headers(bearer, mini.user("owner"))
    )
    assert other.status_code == 404  # an export is its requester's


async def test_export_resource_roles_formats_and_filters(
    app: FastAPI,
    client: AsyncClient,
    mini: Mini,
    bearer: Bearer,
    step_up: Bearer,
    db_session: AsyncSession,
) -> None:
    accountant = headers(bearer, mini.user("accountant"), step_up)
    denied = await client.post("/v1/exports", json={"resource": "audit_logs"}, headers=accountant)
    assert denied.status_code == 403 and denied.json()["code"] == "forbidden"
    unknown = await client.post("/v1/exports", json={"resource": "nope"}, headers=accountant)
    assert unknown.status_code == 422 and unknown.json()["code"] == "export_resource_unknown"
    bad = await client.post(
        "/v1/exports", json={"resource": "payments", "filters": {"colour": "red"}},
        headers=accountant,
    )  # fmt: skip
    assert bad.status_code == 422 and bad.json()["code"] == "export_filters_invalid"
    fmt = await client.post(
        "/v1/exports", json={"resource": "payments", "format": "xml"}, headers=accountant
    )
    assert fmt.status_code == 422 and fmt.json()["code"] == "export_format_unsupported"
    # The agronomist reads crop data: phones masked in the export as in GET /v1/farmers.
    agronomist = headers(bearer, mini.user("agronomist"), step_up)
    resp = await client.post(
        "/v1/exports", json={"resource": "farmers", "format": "xlsx"}, headers=agronomist
    )
    assert resp.status_code == 201, resp.text
    rows = read_xlsx_rows(await _download(app, resp.json()["id"], db_session))
    phone = rows[0].index("phone")
    assert len(rows) == 1 + 3 and all(r[phone].startswith("+91******") for r in rows[1:])
    resources = await client.get("/v1/exports/resources", headers=headers(bearer, mini.user("o1")))
    assert {r["name"] for r in resources.json()["items"]} == {"farmers", "orders", "payments",
                                                              "visits", "flags"}  # fmt: skip


async def test_consent_records_export(
    app: FastAPI,
    client: AsyncClient,
    mini: Mini,
    bearer: Bearer,
    step_up: Bearer,
    db_session: AsyncSession,
) -> None:
    await consented_world(mini)
    resp = await client.post(
        "/v1/exports",
        json={"resource": "consent_records", "filters": {"purpose": "marketing"}},
        headers=headers(bearer, mini.user("auditor"), step_up),
    )
    assert resp.status_code == 201, resp.text
    table = list(
        csv.DictReader(
            io.StringIO((await _download(app, resp.json()["id"], db_session)).decode("utf-8-sig"))
        )
    )
    f3 = [r for r in table if r["subject_id"] == str(mini.farmers["f3"].id)]
    assert [bool(r["granted_at"]) for r in f3] == [True, False]  # grant, then the withdrawal
    assert f3[0]["farmer_name"] == mini.farmers["f3"].name
    assert len(table) == 4


# --------------------------------------------------------------------------- schedules
async def test_report_schedule_is_emailed_on_time_once(
    app: FastAPI,
    client: AsyncClient,
    mini: Mini,
    bearer: Bearer,
    step_up: Bearer,
    db_session: AsyncSession,
) -> None:
    await mini.sale("N1", "f1", T0, [("own", 2, 1000)])
    owner = headers(bearer, mini.user("owner"), step_up)
    body = {
        "name": "Weekly orders",
        "resource": "orders",
        "format": "csv",
        "recipients": ["owner@example.com", "director@example.com"],
    }
    invalid = await client.post("/v1/report-schedules", json={**body, "cron": "0 25 * * 1"},
                                headers=owner)  # fmt: skip
    assert invalid.status_code == 422
    no_step = await client.post("/v1/report-schedules", json=body,
                                headers=headers(bearer, mini.user("owner")))  # fmt: skip
    assert no_step.status_code == 401
    created = await client.post("/v1/report-schedules", json=body, headers=owner)
    assert created.status_code == 201, created.text
    schedule = created.json()
    assert schedule["cron"] == "0 8 * * 1" and schedule["timezone"] == "Asia/Kolkata"
    next_run = datetime.fromisoformat(schedule["next_run_at"]).astimezone(IST)
    assert next_run.isoweekday() == 1 and (next_run.hour, next_run.minute) == (8, 0)
    row = await db_session.get(ReportSchedule, uuid.UUID(schedule["id"]))
    assert row is not None
    fire = datetime(2026, 9, 21, 2, 30, tzinfo=UTC)
    row.next_run_at = fire
    await db_session.flush()
    email = FakeEmailSender()
    early = await run_due_schedules(
        db_session, tenant_id=mini.tid, now=fire - timedelta(minutes=1), store=app.state.exports,
        email=email,
    )  # fmt: skip
    assert early.ran == [] and email.sent == []
    report = await run_due_schedules(
        db_session, tenant_id=mini.tid, now=fire, store=app.state.exports, email=email
    )
    assert report.ran == [row.id]
    [message] = email.sent
    assert message.to == ("owner@example.com", "director@example.com")
    assert message.attachments[0].filename.startswith("orders-")
    assert b"total_paise" in message.attachments[0].content
    assert row.next_run_at == fire + timedelta(days=7) and row.last_status == "sent"
    # A second job run at the same fire time (row put back) sends nothing twice.
    row.next_run_at = fire
    await db_session.flush()
    again = await run_due_schedules(
        db_session, tenant_id=mini.tid, now=fire, store=app.state.exports, email=email
    )
    assert again.skipped == 1 and len(email.sent) == 1
    runs = (await db_session.execute(select(ReportRun))).scalars().all()
    assert [(r.kind, r.status, r.recipients) for r in runs] == [("schedule", "sent", 2)]
    listed = await client.get("/v1/report-schedules", headers=headers(bearer, mini.user("auditor")))
    assert [s["id"] for s in listed.json()["items"]] == [schedule["id"]]
    mine = await client.get(
        "/v1/report-schedules", headers=headers(bearer, mini.user("store_manager"))
    )
    assert mine.json()["items"] == []  # not an admin: own schedules only
    patched = await client.patch(
        f"/v1/report-schedules/{schedule['id']}", json={"cron": "30 7 * * *"}, headers=owner
    )
    assert patched.status_code == 200 and patched.json()["cron"] == "30 7 * * *"
    gone = await client.delete(
        f"/v1/report-schedules/{schedule['id']}", headers=headers(bearer, mini.user("owner"))
    )
    assert gone.status_code == 204


async def test_schedule_fails_cleanly_when_the_owner_left(
    app: FastAPI, mini: Mini, db_session: AsyncSession
) -> None:
    manager = mini.user("store_manager")
    fire = datetime(2026, 9, 21, 2, 30, tzinfo=UTC)
    row = ReportSchedule(
        tenant_id=mini.tid, name="x", resource="orders", format="csv", filters={},
        recipients=["m@example.com"], cron="0 8 * * 1", owner_id=manager.id, next_run_at=fire,
    )  # fmt: skip
    await mini.add(row)
    manager.status = "disabled"
    await db_session.flush()
    email = FakeEmailSender()
    report = await run_due_schedules(
        db_session, tenant_id=mini.tid, now=fire, store=app.state.exports, email=email
    )
    assert report.failed == [row.id] and email.sent == [] and row.last_status == "failed"
