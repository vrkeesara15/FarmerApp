"""VA-E05 — confirmation anomalies (FA-016) over the last ``window_days``.

* **Same OTP phone**: the SMS codes that confirmed visits (``visit_confirmation`` of channel
  ``sms_otp``) went to the phone of their OTP challenge (``otp_challenge.phone``). A phone
  that received the codes for visits to ``min_farmers_per_phone`` or more different farmers
  is one person confirming for many (farmer phones are unique per tenant, so this is a
  phone number changed to someone else's, or codes routed to a helper).
* **Same farmer-side device**: ``app_push`` / ``qr`` confirmations are completed on the
  farmer's phone and record its ``X-Device-Id`` (``confirmed_via_device_id``). One device
  confirming visits to ``min_farmers_per_device`` or more farmers means the "farmer" app is
  in one pair of hands. (``sms_otp`` codes are *typed* on the officer's phone by design, so
  that channel's device is never compared.)

Each finding is about the officer with the most of the confirmations in question (one
officer in the usual case); the evidence lists every confirmation, visit and farmer and the
masked phone (never the full number). Batch (nightly). Key ``phone:<hash>:<ISO week>`` /
``device:<id>:<ISO week>``: a pattern that persists is raised again at most once a week.

Params: ``min_farmers_per_phone``, ``min_farmers_per_device``, ``window_days``.
"""

from __future__ import annotations

import uuid
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import Select, select

from farmerapp.auth.models import OtpChallenge
from farmerapp.auth.providers import mask_phone
from farmerapp.pii.crypto import phone_hash
from farmerapp.rules.checks.common import IST
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.visits.models import (
    ConfirmationChannel,
    ConfirmationStatus,
    Visit,
    VisitConfirmation,
)


@dataclass(frozen=True)
class _Confirmation:
    id: uuid.UUID
    visit: uuid.UUID
    officer: uuid.UUID
    farmer: uuid.UUID
    at: datetime


def _week(rows: list[_Confirmation]) -> str:
    year, week, _ = max(r.at for r in rows).astimezone(IST).isocalendar()
    return f"{year}-W{week:02d}"


def _finding(
    rows: list[_Confirmation], *, key: str, title: str, metrics: dict[str, object]
) -> Finding:
    officers = Counter(r.officer for r in rows)
    subject = sorted(officers.items(), key=lambda kv: (-kv[1], str(kv[0])))[0][0]
    farmers = sorted({r.farmer for r in rows}, key=str)
    ordered = sorted(rows, key=lambda r: (r.at, str(r.id)))
    return Finding(
        subject_type=Subject.EMPLOYEE,
        subject_id=subject,
        key=key,
        title=title,
        evidence=Evidence(
            records=[record("user", o) for o in sorted(officers, key=str)]
            + [record("visit_confirmation", r.id) for r in ordered]
            + [record("visit", r.visit) for r in ordered]
            + [record("farmer", f) for f in farmers],
            metrics={
                **metrics,
                "farmers": len(farmers),
                "confirmations": len(rows),
                "officers": len(officers),
                "first_at": ordered[0].at.isoformat(),
                "last_at": ordered[-1].at.isoformat(),
            },
        ),
    )


def _base(ctx: RuleContext, since: datetime) -> Select[Any]:
    return (
        select(
            VisitConfirmation.id,
            VisitConfirmation.visit_id,
            Visit.officer_id,
            Visit.farmer_id,
            VisitConfirmation.confirmed_at,
        )
        .join(Visit, Visit.id == VisitConfirmation.visit_id)
        .where(
            VisitConfirmation.tenant_id == ctx.tenant_id,
            VisitConfirmation.status == ConfirmationStatus.CONFIRMED.value,
            VisitConfirmation.confirmed_at >= since,
            VisitConfirmation.confirmed_at <= ctx.now,
            VisitConfirmation.deleted_at.is_(None),
            Visit.deleted_at.is_(None),
        )
    )


async def _same_phone(ctx: RuleContext, since: datetime) -> list[Finding]:
    minimum = int(ctx.param("min_farmers_per_phone"))
    stmt = (
        _base(ctx, since)
        .add_columns(OtpChallenge.phone)
        .join(OtpChallenge, OtpChallenge.id == VisitConfirmation.otp_challenge_id)
        .where(VisitConfirmation.channel == ConfirmationChannel.SMS_OTP.value)
    )
    by_phone: dict[str, list[_Confirmation]] = {}
    for cid, visit, officer, farmer, at, phone in (await ctx.session.execute(stmt)).tuples():
        if at is not None:
            by_phone.setdefault(phone, []).append(_Confirmation(cid, visit, officer, farmer, at))
    findings: list[Finding] = []
    for phone, rows in sorted(by_phone.items()):
        farmers = {r.farmer for r in rows}
        if len(farmers) < minimum:
            continue
        digest = phone_hash(phone)[:16]  # SEC-026 peppered hash: not reversible offline
        findings.append(
            _finding(
                rows,
                key=f"phone:{digest}:{_week(rows)}",
                title=f"One phone received the confirmation codes of {len(farmers)} farmers",
                metrics={"reason": "same_otp_phone", "phone_masked": mask_phone(phone)},
            )
        )
    return findings


async def _same_device(ctx: RuleContext, since: datetime) -> list[Finding]:
    minimum = int(ctx.param("min_farmers_per_device"))
    stmt = (
        _base(ctx, since)
        .add_columns(VisitConfirmation.confirmed_via_device_id)
        .where(
            VisitConfirmation.channel.in_(
                [ConfirmationChannel.APP_PUSH.value, ConfirmationChannel.QR.value]
            ),
            VisitConfirmation.confirmed_via_device_id.is_not(None),
        )
    )
    by_device: dict[str, list[_Confirmation]] = {}
    for cid, visit, officer, farmer, at, device in (await ctx.session.execute(stmt)).tuples():
        if at is not None and device is not None:
            by_device.setdefault(device, []).append(_Confirmation(cid, visit, officer, farmer, at))
    findings: list[Finding] = []
    for device, rows in sorted(by_device.items()):
        farmers = {r.farmer for r in rows}
        if len(farmers) < minimum:
            continue
        findings.append(
            _finding(
                rows,
                key=f"device:{device[:64]}:{_week(rows)}",
                title=f"One device confirmed visits for {len(farmers)} farmers",
                metrics={"reason": "same_confirm_device", "device_id": device},
            )
        )
    return findings


@rule("VA-E05")
async def check(ctx: RuleContext) -> list[Finding]:
    since = ctx.now - timedelta(days=float(ctx.param("window_days")))
    return [*await _same_phone(ctx, since), *await _same_device(ctx, since)]
