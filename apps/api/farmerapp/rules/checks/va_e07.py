"""VA-E07 — a TA claim whose km differ from the km computed from the duty track by more than
``max_difference_share`` (SPEC 6.3: 15 %).

Claims (FA-023) are read through ``TravelClaimPort`` (``farmerapp.rules.ports``): the travel
package registers its adapter and emits ``ta.claim.submitted`` with the claim id
(``farmerapp.rules.events.on_travel_claim_submitted`` in-process, or the Pub/Sub topic). The
computed km is the sum of ``duty_session.km`` (FA-010 / VV-006, set at duty end) of the
sessions the claim names, else of the officer's sessions that started on the claim's IST day.
A claim whose sessions are still open (no km yet) is not judged. Differences under
``min_difference_km`` are ignored; a claim with no computed km at all is flagged when it
claims at least ``min_difference_km``.

Only **vehicle** claims are compared: the claim type must be one of ``vehicle_claim_types``
(``fuel``, ``own_vehicle``). A fare — a bus ticket and the like — buys a ride whose price
follows the operator's tariff, not the officer's own distance, so comparing its implied km
with the duty track would flag honest claims; ``bus`` / ``other`` claims are left to the
cluster head's approval (FA-023).

Event mode (``subject_ids`` = claim ids). One flag per claim (key ``claim:<id>``).
"""

from __future__ import annotations

from decimal import Decimal

from sqlalchemy import select

from farmerapp.location.models import DutySession
from farmerapp.rules.checks.common import ist_day_bounds
from farmerapp.rules.ports import get_ports
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject


@rule("VA-E07")
async def check(ctx: RuleContext) -> list[Finding]:
    if not ctx.subject_ids:
        return []  # event rule: the event names the claims
    max_share = float(ctx.param("max_difference_share"))
    min_km = float(ctx.param("min_difference_km"))
    vehicle_types = {str(t) for t in ctx.param("vehicle_claim_types")}
    claims = await get_ports().travel_claims.claims(
        ctx.session, ctx.tenant_id, claim_ids=ctx.subject_ids
    )
    findings: list[Finding] = []
    for claim in claims:
        if claim.claim_type not in vehicle_types:
            continue  # a fare (bus and the like) is not distance-based: never judged here
        stmt = select(DutySession.id, DutySession.km, DutySession.end_at).where(
            DutySession.tenant_id == ctx.tenant_id,
            DutySession.officer_id == claim.officer_id,
            DutySession.deleted_at.is_(None),
        )
        if claim.duty_session_ids:
            stmt = stmt.where(DutySession.id.in_(claim.duty_session_ids))
        else:
            start, end = ist_day_bounds(claim.day)
            stmt = stmt.where(DutySession.start_at >= start, DutySession.start_at < end)
        sessions = (await ctx.session.execute(stmt.order_by(DutySession.start_at))).tuples().all()
        if any(km is None for _sid, km, _end in sessions):
            continue  # a session without km yet (still open): judge the claim later
        computed = sum((Decimal(km or 0) for _sid, km, _end in sessions), Decimal(0))
        claimed = Decimal(claim.claimed_km)
        diff = abs(claimed - computed)
        if float(diff) < min_km:
            continue
        share = float(diff / computed) if computed > 0 else None
        if share is not None and share <= max_share:
            continue
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=claim.officer_id,
                key=f"claim:{claim.id}",
                title=f"TA claim {claimed} km vs {computed} km computed from the duty track",
                evidence=Evidence(
                    records=[record("user", claim.officer_id), record("ta_claim", claim.id)]
                    + [record("duty_session", sid) for sid, _km, _end in sessions],
                    metrics={
                        "reason": "ta_km_mismatch",
                        "day": claim.day.isoformat(),
                        "claim_type": claim.claim_type,
                        "claimed_km": float(claimed),
                        "computed_km": float(computed),
                        "difference_km": float(diff),
                        "difference_share": round(share, 3) if share is not None else None,
                        "max_difference_share": max_share,
                    },
                ),
            )
        )
    return findings
