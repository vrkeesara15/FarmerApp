"""VA-F09 — consent missing or withdrawn, but the farmer is in a campaign segment.

Segment membership is read through ``SegmentMembershipPort`` (``farmerapp.rules.ports``):
campaigns arrive with WC-008, and until that package registers its adapter the null adapter
returns no members, so the rule raises nothing. The consent state is the latest
``consent_record`` of the farmer for ``params.consent_purpose`` (FM-002: append-only; the
newest row is the current state): no row -> ``consent_missing``, a withdrawal ->
``consent_withdrawn``.

Batch (nightly). One flag per farmer and consent state (key ``consent:<purpose>:<latest
record id | none>``), so a later withdrawal raises a new flag; the evidence lists the
segments.
"""

from __future__ import annotations

import uuid

from sqlalchemy import select

from farmerapp.farmers.models import ConsentRecord, ConsentSubject, Farmer
from farmerapp.rules.ports import SegmentMember, get_ports
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject


@rule("VA-F09")
async def check(ctx: RuleContext) -> list[Finding]:
    purpose = str(ctx.param("consent_purpose"))
    members = await get_ports().segments.members(ctx.session, ctx.tenant_id, ctx.subject_ids)
    if not members:
        return []
    by_farmer: dict[uuid.UUID, list[SegmentMember]] = {}
    for m in members:
        by_farmer.setdefault(m.farmer_id, []).append(m)
    alive = set(
        (
            await ctx.session.execute(
                select(Farmer.id).where(
                    Farmer.tenant_id == ctx.tenant_id,
                    Farmer.id.in_(list(by_farmer)),
                    Farmer.deleted_at.is_(None),
                )
            )
        ).scalars()
    )
    latest: dict[uuid.UUID, ConsentRecord] = {}
    rows = await ctx.session.execute(
        select(ConsentRecord)
        .where(
            ConsentRecord.tenant_id == ctx.tenant_id,
            ConsentRecord.subject_type == ConsentSubject.FARMER.value,
            ConsentRecord.subject_id.in_(list(alive)),
            ConsentRecord.purpose == purpose,
        )
        .order_by(ConsentRecord.subject_id, ConsentRecord.created_at.desc(), ConsentRecord.id)
    )
    for row in rows.scalars():
        latest.setdefault(row.subject_id, row)
    findings: list[Finding] = []
    for farmer_id in sorted(alive, key=str):
        current = latest.get(farmer_id)
        if current is not None and current.granted_at is not None:
            continue
        reason = "consent_missing" if current is None else "consent_withdrawn"
        segments = sorted({m.segment_id for m in by_farmer[farmer_id]})
        campaigns = sorted({m.campaign_id for m in by_farmer[farmer_id] if m.campaign_id})
        records = [record("farmer", farmer_id)]
        if current is not None:
            records.append(record("consent_record", current.id))
        findings.append(
            Finding(
                subject_type=Subject.FARMER,
                subject_id=farmer_id,
                key=f"consent:{purpose}:{current.id if current is not None else 'none'}",
                title=f"In {len(segments)} campaign segment(s) without {purpose} consent",
                evidence=Evidence(
                    records=records,
                    metrics={
                        "reason": reason,
                        "consent_purpose": purpose,
                        "segments": segments,
                        "campaigns": campaigns,
                        "withdrawn_at": (
                            current.withdrawn_at.isoformat()
                            if current is not None and current.withdrawn_at
                            else None
                        ),
                    },
                ),
            )
        )
    return findings
