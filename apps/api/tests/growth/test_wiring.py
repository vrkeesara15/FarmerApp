"""The two seams the parent merge wires between the M7 branches (docs/prs/M7-growth-api.md
"Wiring the parent must do"):

* VA-F09 (rules branch) reads campaign audiences through ``SegmentMembershipPort``; the
  growth branch registers ``farmerapp.campaigns.membership.CAMPAIGN_SEGMENT_MEMBERSHIP``.
  End to end here: a farmer in a scheduled campaign's audience who withdraws marketing
  consent is flagged by the real rule engine, not by a fake port.
* FA-024 (field-agent branch) reads the incentive earned through ``IncentivePort``; the
  growth branch registers ``farmerapp.incentives.service.incentive_for``. End to end here:
  ``GET /v1/me/performance`` returns the payout computed by hand from the rule document.
"""

from __future__ import annotations

from datetime import date, timedelta

from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.campaigns import membership
from farmerapp.campaigns import service as campaign_service
from farmerapp.campaigns.models import CampaignChannel
from farmerapp.flags.models import Flag
from farmerapp.incentives import service as incentive_service
from farmerapp.incentives.models import TargetSubject
from farmerapp.incentives.performance_port import SERVICE_INCENTIVES, ServiceIncentives
from farmerapp.rules import ports
from farmerapp.rules.engine import run_rules
from farmerapp.rules.schema import Mode
from tests.analytics.builders import Mini
from tests.authz.conftest import Bearer
from tests.growth.conftest import T0, consent, consented_world, headers
from tests.growth.test_campaigns import DLT, make, set_settings
from tests.growth.test_incentives import MARCH, active_rules, march_activity


# --------------------------------------------------------------------------- VA-F09
async def test_va_f09_fires_for_a_segment_member_without_consent(
    mini: Mini, db_session: AsyncSession
) -> None:
    """The nightly rules run raises VA-F09 for a farmer who is still in a scheduled
    campaign's frozen audience when their marketing consent is withdrawn."""
    await consented_world(mini)
    await set_settings(mini, **DLT)
    campaign = await make(mini, CampaignChannel.SMS)
    await campaign_service.schedule_campaign(
        db_session, campaign, send_at=T0 + timedelta(days=1), now=T0
    )
    f1 = mini.farmers["f1"]
    await consent(mini, f1, granted=False, at=T0 + timedelta(hours=1))

    previous = ports.get_ports().segments
    membership.register()
    try:
        assert isinstance(ports.get_ports().segments, membership.CampaignSegmentMembership)
        report = await run_rules(
            db_session, mini.tid, Mode.BATCH, rule_ids=["VA-F09"], now=T0 + timedelta(hours=2)
        )
    finally:
        ports.set_ports(segments=previous)

    assert report.raised["VA-F09"] == 1
    flags = (
        (
            await db_session.execute(
                select(Flag).where(Flag.tenant_id == mini.tid, Flag.rule_id == "VA-F09")
            )
        )
        .scalars()
        .all()
    )
    [flag] = flags
    assert flag.subject_id == f1.id and flag.severity == "high"
    metrics = flag.evidence["metrics"]
    assert metrics["reason"] == "consent_withdrawn"
    assert metrics["campaigns"] == [str(campaign.id)]
    assert {"type": "farmer", "id": str(f1.id)} in flag.evidence["records"]


async def test_the_api_registers_the_segment_port(app: FastAPI) -> None:
    """``create_app`` wires the real adapter (the rules jobs and the worker do the same)."""
    assert isinstance(ports.get_ports().segments, membership.CampaignSegmentMembership)


# --------------------------------------------------------------------------- FA-024
async def test_my_performance_shows_the_hand_computed_incentive(
    app: FastAPI, client: AsyncClient, mini: Mini, bearer: Bearer, db_session: AsyncSession
) -> None:
    """March 2027 for officer O1 under the ``tests.growth.test_incentives`` rule document:

    * visits 5 verified -> slabs 0-2 at 0, 2-4 at 20.00/visit = 200.00, 4-5 at 150.00 = 350.00
    * sales 800.00 at 200 bp = 16.00 (under the 500.00 component cap)
    * own brand share 0.25 < 0.5 -> 0; new farmers 2 x 50.00 = 100.00
    * 466.00 x 1.5 (sales attainment 800.00 / 600.00 >= 1) = 699.00, under the 2000.00 cap
    * minus the clawback of the February order cancelled in March: 400.00 at 200 bp = 8.00

    = **691.00 = 69100 paise**, the same number ``tests/growth/test_incentives.py`` gets from
    the engine, now through the FA-024 port and the officer's own endpoint.
    """
    assert isinstance(app.state.incentives, ServiceIncentives)  # create_app wired WC-009
    await march_activity(mini)
    await active_rules(mini)
    officer = mini.user("o1")
    await incentive_service.upsert_target(
        db_session,
        mini.user("owner"),
        month=MARCH,
        subject_type=TargetSubject.OFFICER,
        subject_id=officer.id,
        values={"sales_paise": 60000, "visits_verified": 10},
    )

    resp = await client.get(
        "/v1/me/performance",
        params={"from": str(MARCH), "to": str(date(2027, 3, 31))},
        headers=headers(bearer, officer),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["incentive_earned_paise"] == 69100

    direct = await SERVICE_INCENTIVES.earned_paise(
        db_session, mini.tid, officer.id, MARCH, date(2027, 3, 31)
    )
    assert direct == 69100  # the port itself, inclusive last day


async def test_incentive_is_null_without_active_rules(
    client: AsyncClient, mini: Mini, bearer: Bearer
) -> None:
    """No rule set: the port answers ``None`` (the app shows "--", never a fake zero)."""
    await march_activity(mini)
    resp = await client.get(
        "/v1/me/performance",
        params={"from": str(MARCH), "to": str(date(2027, 3, 31))},
        headers=headers(bearer, mini.user("o1")),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["incentive_earned_paise"] is None
