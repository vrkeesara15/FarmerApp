"""WC-008 campaigns and AN-008 ROI: only consented farmers are selectable (query + send-time
re-check), channels through the provider adapters / notification rows, throttled sends,
delivery status, conversion attribution and own-brand lift against a holdout."""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.providers import FakeProvider
from farmerapp.campaigns import service
from farmerapp.campaigns.membership import CampaignSegmentMembership
from farmerapp.campaigns.models import (
    Campaign,
    CampaignChannel,
    CampaignRecipient,
    RecipientArm,
    RecipientStatus,
)
from farmerapp.campaigns.segments import Segment, SegmentContext, count_segment, segment_query
from farmerapp.notifications.models import Notification
from tests.analytics.builders import Mini
from tests.authz.conftest import Bearer
from tests.growth.conftest import T0, consent, consented_world, headers

DLT = {"campaigns": {"dlt_templates": {"promo": "1107160000000000001"}}}


def ctx(m: Mini) -> SegmentContext:
    return SegmentContext(tenant_id=m.tid, now=T0)


async def ids(session: AsyncSession, m: Mini, segment: Segment) -> set[str]:
    rows = (await session.execute(segment_query(segment, ctx(m)))).scalars()
    names = {f.id: k for k, f in m.farmers.items()}
    return {names[r] for r in rows}


async def set_settings(m: Mini, **settings: Any) -> None:
    m.tenant.settings = {**(m.tenant.settings or {}), **settings}
    await m.session.flush()


async def make(
    m: Mini, channel: CampaignChannel, *, segment: Segment | None = None, **kw: Any
) -> Campaign:
    return await service.create_campaign(
        m.session,
        m.user("owner"),
        name="Kharif push",
        channel=channel,
        segment=segment or Segment(),
        messages={"te": "Telugu text", "en": "English text"},
        template_key=kw.pop("template_key", "promo"),
        attribution_days=kw.pop("attribution_days", None),
        holdout_pct=kw.pop("holdout_pct", 0),
        notes=None,
    )


async def recipients(session: AsyncSession, campaign: Campaign) -> dict[uuid.UUID, Any]:
    rows = (
        await session.execute(
            select(CampaignRecipient).where(CampaignRecipient.campaign_id == campaign.id)
        )
    ).scalars()
    return {r.farmer_id: r for r in rows}


# --------------------------------------------------------------------------- segments
async def test_only_consented_farmers_are_selectable(mini: Mini, db_session: AsyncSession) -> None:
    await consented_world(mini)
    assert await ids(db_session, mini, Segment()) == {"f1", "f2"}
    counted = await count_segment(db_session, Segment(), ctx(mini))
    assert (counted.count, counted.excluded_no_consent) == (2, 2)  # f3 withdrew, f4 never asked
    # A later re-grant makes f3 selectable again (the latest row is the state).
    await consent(mini, mini.farmers["f3"], granted=True, at=T0 - timedelta(days=1))
    assert await ids(db_session, mini, Segment()) == {"f1", "f2", "f3"}


async def test_segment_criteria(mini: Mini, db_session: AsyncSession) -> None:
    await consented_world(mini)
    await consent(mini, mini.farmers["f3"], granted=True, at=T0 - timedelta(days=1))
    m = mini
    assert await ids(db_session, m, Segment(crop_ids=[m.crops["paddy"].id])) == {"f1"}
    assert await ids(db_session, m, Segment(stages=["vegetative"])) == {"f1", "f3"}
    assert await ids(db_session, m, Segment(districts=["district s1"])) == {"f3"}
    assert await ids(db_session, m, Segment(store_ids=[m.stores["N1"].id])) == {"f1", "f2"}
    await m.sale("N1", "f2", T0 - timedelta(days=5), [("own", 2, 1000)])
    await m.sale("N1", "f1", T0 - timedelta(days=40), [("own", 1, 900)])
    assert await ids(db_session, m, Segment(purchase_within_days=30)) == {"f2"}
    assert await ids(db_session, m, Segment(min_spend_paise=1500)) == {"f2"}
    assert await ids(db_session, m, Segment(no_purchase_within_days=30)) == {"f1", "f3"}
    await m.visit("o1", "f1", T0 - timedelta(days=3))
    assert await ids(db_session, m, Segment(visited_within_days=7)) == {"f1"}
    assert await ids(db_session, m, Segment(not_visited_within_days=7)) == {"f2", "f3"}
    assert await ids(db_session, m, Segment(app_user=True)) == {"f1"}  # f1 has the app login
    assert await ids(db_session, m, Segment(app_user=False)) == {"f2", "f3"}
    with pytest.raises(ValueError, match="exclude each other"):
        Segment(purchase_within_days=5, no_purchase_within_days=5)


# --------------------------------------------------------------------------- sends
async def test_withdrawal_between_build_and_send_is_skipped(
    mini: Mini, db_session: AsyncSession
) -> None:
    await consented_world(mini)
    await set_settings(mini, **DLT)
    campaign = await make(mini, CampaignChannel.SMS)
    await service.schedule_campaign(db_session, campaign, send_at=None, now=T0)
    frozen = await recipients(db_session, campaign)
    assert set(frozen) == {mini.farmers["f1"].id, mini.farmers["f2"].id}
    assert campaign.audience_size == 2 and campaign.status == "scheduled"
    # f2 withdraws after the audience was frozen, before the send.
    await consent(mini, mini.farmers["f2"], granted=False, at=T0 + timedelta(minutes=1))
    provider = FakeProvider()
    sender = service.CampaignSender(sms=provider, whatsapp=provider)
    report = await service.send_due_campaigns(
        db_session, tenant_id=mini.tid, now=T0 + timedelta(minutes=2), sender=sender
    )
    assert (report.sent, report.skipped) == (1, {"consent_withdrawn": 1})
    after = await recipients(db_session, campaign)
    f1, f2 = after[mini.farmers["f1"].id], after[mini.farmers["f2"].id]
    assert f2.status == "skipped" and f2.skip_reason == "consent_withdrawn"
    assert f1.status == "sent" and f1.provider_ref and f1.dlt_template_id == "1107160000000000001"
    assert [m.to for m in provider.sent] == [mini.farmers["f1"].phone]
    assert provider.sent[0].body == "Telugu text"  # the farmer's language (te)
    assert campaign.status == "sent" and campaign.finished_at is not None
    changed = await service.refresh_delivery(
        db_session, tenant_id=mini.tid, now=T0 + timedelta(minutes=3), sender=sender
    )
    assert changed == 1 and f1.status == "delivered"


async def test_sms_needs_a_dlt_template(mini: Mini, db_session: AsyncSession) -> None:
    await consented_world(mini)
    campaign = await make(mini, CampaignChannel.SMS)
    with pytest.raises(service.TemplateMissingError):
        await service.schedule_campaign(db_session, campaign, send_at=None, now=T0)
    wa = await make(mini, CampaignChannel.WHATSAPP)
    with pytest.raises(service.TemplateMissingError) as err:
        await service.schedule_campaign(db_session, wa, send_at=None, now=T0)
    assert err.value.code == "whatsapp_template_missing"


async def test_push_goes_through_notification_rows_and_tracks_opens(
    mini: Mini, db_session: AsyncSession
) -> None:
    await consented_world(mini)
    campaign = await make(mini, CampaignChannel.PUSH, template_key=None)
    await service.schedule_campaign(db_session, campaign, send_at=None, now=T0)
    provider = FakeProvider()
    sender = service.CampaignSender(sms=provider, whatsapp=provider)
    report = await service.send_due_campaigns(db_session, tenant_id=mini.tid, now=T0, sender=sender)
    assert report.sent == 1 and report.skipped == {"no_app": 1}  # f2 has no farmer-app login
    assert provider.sent == []
    note = (
        await db_session.execute(
            select(Notification).where(Notification.kind == service.CAMPAIGN_NOTIFICATION_KIND)
        )
    ).scalar_one()
    assert note.user_id == mini.user("farmer_user").id
    assert note.data["text"] == "Telugu text" and note.data["campaign_id"] == str(campaign.id)
    note.read_at = T0 + timedelta(hours=2)
    await db_session.flush()
    await service.refresh_delivery(
        db_session, tenant_id=mini.tid, now=T0 + timedelta(hours=3), sender=sender
    )
    roi = await service.campaign_roi(db_session, campaign)
    assert roi.opened == 1 and roi.counts["delivered"] == 1


async def test_sends_are_throttled_per_run(mini: Mini, db_session: AsyncSession) -> None:
    await consented_world(mini)
    await set_settings(mini, campaigns={**DLT["campaigns"], "sends_per_run": 1})
    campaign = await make(mini, CampaignChannel.SMS)
    await service.schedule_campaign(db_session, campaign, send_at=T0 + timedelta(hours=1), now=T0)
    provider = FakeProvider()
    sender = service.CampaignSender(sms=provider, whatsapp=provider)
    early = await service.send_due_campaigns(db_session, tenant_id=mini.tid, now=T0, sender=sender)
    assert early.campaigns == 0  # not due yet
    later = T0 + timedelta(hours=1)
    first = await service.send_due_campaigns(
        db_session, tenant_id=mini.tid, now=later, sender=sender
    )
    assert first.sent == 1 and campaign.status == "sending"
    second = await service.send_due_campaigns(
        db_session, tenant_id=mini.tid, now=later + timedelta(minutes=1), sender=sender
    )
    assert second.sent == 1 and campaign.status == "sent"
    assert len(provider.sent) == 2


def test_holdout_split_is_deterministic_and_proportional() -> None:
    campaign = uuid.uuid4()
    farmers = [uuid.uuid4() for _ in range(2000)]
    held = [f for f in farmers if service.in_holdout(campaign, f, 20)]
    assert 0.16 < len(held) / len(farmers) < 0.24
    assert held == [f for f in farmers if service.in_holdout(campaign, f, 20)]
    assert not any(service.in_holdout(campaign, f, 0) for f in farmers)


# --------------------------------------------------------------------------- ROI
async def test_roi_attributes_orders_in_the_window_and_measures_lift(
    mini: Mini, db_session: AsyncSession
) -> None:
    await consented_world(mini)
    await set_settings(mini, **DLT)
    campaign = await make(mini, CampaignChannel.SMS, attribution_days=14)
    await service.schedule_campaign(db_session, campaign, send_at=None, now=T0)
    # Put f2 into the holdout arm (the split is a hash; this pins it for the fixture).
    rows = await recipients(db_session, campaign)
    held = rows[mini.farmers["f2"].id]
    held.arm, held.status = RecipientArm.HOLDOUT.value, RecipientStatus.HOLDOUT.value
    await db_session.flush()
    provider = FakeProvider()
    sender = service.CampaignSender(sms=provider, whatsapp=provider)
    await service.send_due_campaigns(db_session, tenant_id=mini.tid, now=T0, sender=sender)
    # f1 (target): own brand 2 x 1000 inside the window, 1 x 800 multi inside, one too late.
    await mini.sale("N1", "f1", T0 + timedelta(days=2), [("own", 2, 1000), ("multi", 1, 800)])
    await mini.sale("N1", "f1", T0 + timedelta(days=20), [("own", 5, 1000)])
    await mini.sale("N1", "f1", T0 - timedelta(days=1), [("own", 5, 1000)])  # before the send
    # f2 (holdout): multi-brand only in the window.
    await mini.sale("N1", "f2", T0 + timedelta(days=3), [("multi", 1, 1000)])
    roi = await service.campaign_roi(db_session, campaign)
    assert roi.target.orders == 1 and roi.target.revenue_paise == 2800
    assert roi.target.converted_farmers == 1 and roi.target.conversion_rate == 1.0
    assert roi.target.own_brand_share == round(2000 / 2800, 4)
    assert roi.holdout is not None and roi.holdout.orders == 1
    assert roi.holdout.own_brand_share == 0.0
    assert roi.own_brand_lift == round(2000 / 2800, 4)
    assert roi.conversion_lift == 0.0
    # A later campaign reaching f1 before an order takes the credit (last touch).
    second = await make(mini, CampaignChannel.SMS)
    await service.schedule_campaign(db_session, second, send_at=None, now=T0 + timedelta(days=4))
    await service.send_due_campaigns(
        db_session, tenant_id=mini.tid, now=T0 + timedelta(days=4), sender=sender
    )
    await mini.sale("N1", "f1", T0 + timedelta(days=5), [("own", 1, 1000)])
    first = await service.campaign_roi(db_session, campaign)
    latest = await service.campaign_roi(db_session, second)
    assert first.target.orders == 1  # unchanged
    assert latest.target.orders == 1 and latest.target.revenue_paise == 1000


# --------------------------------------------------------------------------- VA-F09 port
async def test_segment_membership_adapter_reports_members_without_consent(
    mini: Mini, db_session: AsyncSession
) -> None:
    await consented_world(mini)
    await set_settings(mini, **DLT)
    campaign = await make(mini, CampaignChannel.SMS)
    await service.schedule_campaign(db_session, campaign, send_at=T0 + timedelta(days=1), now=T0)
    port = CampaignSegmentMembership()
    assert await port.farmers_in_segments(db_session, mini.tid, now=T0) == {
        mini.farmers["f1"].id,
        mini.farmers["f2"].id,
    }
    assert await port.members_without_consent(db_session, mini.tid, now=T0) == []
    await consent(mini, mini.farmers["f1"], granted=False, at=T0 + timedelta(hours=1))
    missing = await port.members_without_consent(db_session, mini.tid, now=T0)
    assert [(m.farmer_id, m.campaign_id) for m in missing] == [(mini.farmers["f1"].id, campaign.id)]


# --------------------------------------------------------------------------- API
async def test_campaign_api_flow(
    client: AsyncClient, mini: Mini, bearer: Bearer, db_session: AsyncSession
) -> None:
    await consented_world(mini)
    await set_settings(mini, **DLT)
    owner = headers(bearer, mini.user("owner"))
    count = await client.post(
        "/v1/campaigns/segment-count",
        json={"segment": {"store_ids": [str(mini.stores["N1"].id)]}},
        headers=owner,
    )
    assert count.status_code == 200, count.text
    assert count.json() == {"count": 2, "excluded_no_consent": 1}
    body = {
        "name": "Rabi seeds",
        "channel": "sms",
        "segment": {"store_ids": [str(mini.stores["N1"].id)]},
        "messages": {"te": "Telugu", "en": "English"},
        "template_key": "promo",
    }
    auditor = headers(bearer, mini.user("auditor"))
    denied = await client.post("/v1/campaigns", json=body, headers=auditor)
    assert denied.status_code == 403
    bad = await client.post("/v1/campaigns", json={**body, "messages": {"xx": "?"}}, headers=owner)
    assert bad.status_code == 422
    created = await client.post("/v1/campaigns", json=body, headers=owner)
    assert created.status_code == 201, created.text
    cid = created.json()["id"]
    assert created.json()["status"] == "draft" and created.json()["attribution_days"] == 14
    patched = await client.patch(f"/v1/campaigns/{cid}", json={"name": "Rabi"}, headers=owner)
    assert patched.json()["name"] == "Rabi"
    scheduled = await client.post(f"/v1/campaigns/{cid}/schedule", json={}, headers=owner)
    assert scheduled.status_code == 200, scheduled.text
    assert scheduled.json()["status"] == "scheduled" and scheduled.json()["audience_size"] == 2
    again = await client.patch(f"/v1/campaigns/{cid}", json={"name": "x"}, headers=owner)
    assert again.status_code == 409 and again.json()["code"] == "invalid_campaign_state"
    listed = await client.get(f"/v1/campaigns/{cid}/recipients", headers=auditor)
    assert listed.status_code == 200
    page = listed.json()
    assert page["counts"] == {"pending": 2}
    assert all(item["phone_masked"].startswith("+91******") for item in page["items"])
    roi = await client.get(f"/v1/campaigns/{cid}/roi", headers=auditor)
    assert roi.status_code == 200 and roi.json()["audience"] == 2 and roi.json()["opened"] is None
    all_campaigns = await client.get("/v1/campaigns", headers=auditor)
    assert [c["id"] for c in all_campaigns.json()["items"]] == [cid]
    cancelled = await client.post(f"/v1/campaigns/{cid}/cancel", headers=owner)
    assert cancelled.json()["status"] == "cancelled"
    row = await db_session.get(Campaign, uuid.UUID(cid))
    assert row is not None
    skipped = await recipients(db_session, row)
    assert {r.skip_reason for r in skipped.values()} == {"campaign_cancelled"}


async def test_scheduling_an_sms_without_template_is_422(
    client: AsyncClient, mini: Mini, bearer: Bearer
) -> None:
    await consented_world(mini)
    owner = headers(bearer, mini.user("owner"))
    created = await client.post(
        "/v1/campaigns",
        json={"name": "x", "channel": "sms", "messages": {"en": "hi"}, "template_key": "nope"},
        headers=owner,
    )
    resp = await client.post(
        f"/v1/campaigns/{created.json()['id']}/schedule", json={}, headers=owner
    )
    assert resp.status_code == 422 and resp.json()["code"] == "dlt_template_missing"
