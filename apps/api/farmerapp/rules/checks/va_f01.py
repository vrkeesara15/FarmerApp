"""VA-F01 — farmer phone: E.164 Indian mobile, OTP-verified, not a staff or blocklisted phone.

Registration already *rejects* a malformed phone, a duplicate and a staff phone (FA-012,
``farmers.service._check_phone``). This rule flags what can still go wrong afterwards or
outside that path: imported rows with a malformed phone, a phone that became a staff
account's phone later, a phone on the tenant's blocklist (``params.blocklist``), and a farmer
whose phone is still not OTP-verified ``unverified_grace_hours`` after registration (offline
captures verify later, FA-012).

Params: ``phone_pattern`` (regex), ``unverified_grace_hours``, ``blocklist`` (list of E.164).
"""

from __future__ import annotations

import re
from datetime import timedelta

from sqlalchemy import select

from farmerapp.auth.models import User, UserRole
from farmerapp.farmers.models import Farmer
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject


@rule("VA-F01")
async def check(ctx: RuleContext) -> list[Finding]:
    pattern = re.compile(str(ctx.param("phone_pattern")))
    grace = timedelta(hours=float(ctx.param("unverified_grace_hours")))
    blocklist = {str(p) for p in ctx.param("blocklist")}
    stmt = select(Farmer).where(Farmer.tenant_id == ctx.tenant_id, Farmer.deleted_at.is_(None))
    if ctx.subject_ids is not None:
        stmt = stmt.where(Farmer.id.in_(ctx.subject_ids))
    farmers = (await ctx.session.execute(stmt)).scalars().all()
    if not farmers:
        return []
    staff = set(
        (
            await ctx.session.execute(
                select(User.phone).where(
                    User.tenant_id == ctx.tenant_id,
                    User.role != UserRole.FARMER.value,
                    User.deleted_at.is_(None),
                    User.phone.in_([f.phone for f in farmers]),
                )
            )
        ).scalars()
    )
    findings: list[Finding] = []
    for farmer in farmers:
        reasons: list[str] = []
        if not pattern.fullmatch(farmer.phone):
            reasons.append("phone_format")
        if farmer.phone in staff:
            reasons.append("staff_phone")
        if farmer.phone in blocklist:
            reasons.append("blocklisted_phone")
        if not farmer.phone_verified and farmer.created_at + grace <= ctx.now:
            reasons.append("phone_not_verified")
        if not reasons:
            continue
        findings.append(
            Finding(
                subject_type=Subject.FARMER,
                subject_id=farmer.id,
                key="phone",
                title="Farmer phone needs review: "
                + ", ".join(r.replace("_", " ") for r in reasons),
                evidence=Evidence(
                    records=[record("farmer", farmer.id)],
                    metrics={
                        "reasons": reasons,
                        "phone_last4": farmer.phone_last4,
                        "phone_verified": farmer.phone_verified,
                        "registered_at": farmer.created_at.isoformat(),
                    },
                ),
            )
        )
    return findings
