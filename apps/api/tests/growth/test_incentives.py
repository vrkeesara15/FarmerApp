"""WC-009 targets and the incentive rules engine. Acceptance: "incentive computed matches rule
on test data" — every expected amount below is computed by hand from the rule document."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.incentives import service
from farmerapp.incentives.models import TargetSubject
from farmerapp.incentives.rules import Metrics, RuleDefinition, evaluate
from farmerapp.orders.models import OrderStatusEvent
from tests.analytics.builders import Mini, ist
from tests.authz.conftest import Bearer
from tests.growth.conftest import headers

MARCH = date(2027, 3, 1)
RULES: dict[str, Any] = {
    "eligibility": {"min_verified_visits": 2},
    "components": [
        {
            "id": "visits",
            "metric": "verified_visits",
            "kind": "slab_per_unit",
            "slabs": [
                {"from": 0, "to": 2, "rate_paise": 0},
                {"from": 2, "to": 4, "rate_paise": 10000},
                {"from": 4, "rate_paise": 15000},
            ],
        },
        {
            "id": "sales",
            "metric": "sales_paise",
            "kind": "percent",
            "rate_bp": 200,
            "cap_paise": 50000,
        },
        {
            "id": "own_brand",
            "metric": "own_brand_share",
            "kind": "threshold",
            "threshold": 0.5,
            "amount_paise": 20000,
        },
        {"id": "farmers", "metric": "new_farmers", "kind": "per_unit", "rate_paise": 5000},
    ],
    "multipliers": [{"metric": "attainment.sales_paise", "gte": 1.0, "factor": 1.5}],
    "cap_paise": 200000,
    "clawback": {"cancelled_orders": True},
}


# --------------------------------------------------------------------------- pure engine
def test_evaluate_matches_the_hand_computed_payout() -> None:
    definition = RuleDefinition.model_validate(RULES)
    metrics = Metrics(
        verified_visits=5,
        visits=8,
        new_farmers=2,
        sales_paise=80000,
        own_brand_sales_paise=20000,
        own_brand_share=0.25,
        collections_paise=0,
        cancelled_prior_sales_paise=40000,
    )
    result = evaluate(definition, metrics, {"sales_paise": 60000})
    lines = {line.component: line.amount_paise for line in result.lines}
    # visits: units 2..4 at 100.00 = 200.00, unit 4..5 at 150.00 -> 350.00
    # sales: 2 % of 800.00 = 16.00; own brand 25 % < 50 % -> 0; farmers 2 x 50.00 = 100.00
    assert lines == {"visits": 35000, "sales": 1600, "own_brand": 0, "farmers": 10000}
    assert result.subtotal_paise == 46600
    assert result.multiplier == 1.5  # 800.00 / 600.00 target >= 1.0
    assert result.gross_paise == 69900
    assert result.clawback_paise == 800  # 2 % of the 400.00 cancelled from last month
    assert result.amount_paise == 69100 and result.eligible


def test_caps_multipliers_and_eligibility() -> None:
    definition = RuleDefinition.model_validate(RULES)
    big = Metrics(verified_visits=40, sales_paise=10_000_000, own_brand_share=0.6)
    result = evaluate(definition, big, {"sales_paise": 1})
    lines = {line.component: line for line in result.lines}
    assert lines["sales"].amount_paise == 50000 and lines["sales"].capped  # 2 % capped at 500.00
    assert lines["own_brand"].amount_paise == 20000
    assert result.gross_paise == 200000 and result.capped  # total cap after the 1.5 multiplier
    # No target: no multiplier. Below the minimum verified visits: not eligible, 0 payable.
    assert evaluate(definition, Metrics(verified_visits=3), {}).multiplier == 1.0
    low = evaluate(definition, Metrics(verified_visits=1, new_farmers=4), {})
    assert not low.eligible and low.amount_paise == 0 and low.reasons
    flat = RuleDefinition.model_validate(
        {
            "components": [
                {
                    "id": "tier",
                    "metric": "collections_paise",
                    "kind": "slab_flat",
                    "slabs": [
                        {"from": 0, "to": 100000, "amount_paise": 0},
                        {"from": 100000, "to": 500000, "amount_paise": 25000},
                        {"from": 500000, "amount_paise": 60000},
                    ],
                }
            ]
        }
    )
    amounts = [
        evaluate(flat, Metrics(collections_paise=v)).amount_paise for v in (99999, 100000, 600000)
    ]
    assert amounts == [0, 25000, 60000]


@pytest.mark.parametrize(
    "broken",
    [
        {"components": []},
        {"components": [{"id": "a", "metric": "sales_paise", "kind": "percent"}]},
        {"components": [{"id": "a", "metric": "verified_visits", "kind": "percent", "rate_bp": 1}]},
        {"components": [{"id": "a", "metric": "unknown", "kind": "per_unit", "rate_paise": 1}]},
        {
            "components": [
                {
                    "id": "a",
                    "metric": "visits",
                    "kind": "slab_per_unit",
                    "slabs": [
                        {"from": 0, "to": 5, "rate_paise": 1},
                        {"from": 3, "rate_paise": 2},
                    ],
                }
            ]
        },
        {
            "components": [
                {"id": "a", "metric": "visits", "kind": "per_unit", "rate_paise": 1},
                {"id": "a", "metric": "visits", "kind": "per_unit", "rate_paise": 1},
            ]
        },
    ],
)
def test_invalid_rule_documents_are_rejected(broken: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        RuleDefinition.model_validate(broken)


# --------------------------------------------------------------------------- live metrics
async def march_activity(m: Mini) -> None:
    """O1 in March 2027 (IST): 5 verified + 2 partial + 1 unverified visits, two new farmers,
    two live orders (300.00 incl. 200.00 own brand, 500.00), one order placed and cancelled in
    March (never counts), and a February order of 400.00 cancelled on 5 March (clawback)."""
    for day in range(1, 6):
        await m.visit("o1", "f1", ist(date(2027, 3, day), 10), score=80)
    await m.visit("o1", "f2", ist(date(2027, 3, 6), 10), score=50)
    await m.visit("o1", "f2", ist(date(2027, 3, 7), 10), score=45)
    await m.visit("o1", "f2", ist(date(2027, 3, 8), 10), score=20)
    await m.visit("o1", "f1", ist(date(2027, 2, 28), 10), score=90)  # February
    await m.visit("o2", "f3", ist(date(2027, 3, 2), 10), score=90)  # another officer
    await m.farmer("n1", "N1", "o1", None, created_at=ist(date(2027, 3, 3), 9))
    await m.farmer("n2", "N1", "o1", None, created_at=ist(date(2027, 3, 20), 9))
    await m.farmer("n3", "N1", "o1", None, created_at=ist(date(2027, 4, 1), 9))  # April
    await m.sale("N1", "f1", ist(date(2027, 3, 4), 11), [("own", 20, 1000), ("multi", 10, 1000)],
                 placed_by="o1")  # fmt: skip
    await m.sale("N1", "f2", ist(date(2027, 3, 31), 23), [("multi", 50, 1000)], placed_by="o1",
                 status="placed")  # fmt: skip
    await m.sale("N1", "f2", ist(date(2027, 3, 10), 11), [("own", 100, 1000)], placed_by="o1",
                 status="cancelled")  # fmt: skip
    feb = await m.sale(
        "N1", "f1", ist(date(2027, 2, 20), 11), [("multi", 40, 1000)], placed_by="o1",
        status="cancelled",
    )  # fmt: skip
    await m.add(
        OrderStatusEvent(
            tenant_id=m.tid,
            order_id=feb.id,
            from_status="placed",
            to_status="cancelled",
            created_at=ist(date(2027, 3, 5), 12),
        )
    )


async def active_rules(m: Mini, definition: dict[str, Any] | None = None) -> Any:
    return await service.create_rule_set(
        m.session, m.user("owner"), name="FY27", definition=definition or RULES, activate=True
    )


async def test_preview_from_live_data_matches_the_rule(
    mini: Mini, db_session: AsyncSession
) -> None:
    await march_activity(mini)
    await active_rules(mini)
    officer = mini.user("o1")
    await service.upsert_target(
        db_session,
        mini.user("owner"),
        month=MARCH,
        subject_type=TargetSubject.OFFICER,
        subject_id=officer.id,
        values={"sales_paise": 60000, "visits_verified": 10},
    )
    result = await service.preview(db_session, mini.tid, officer.id, date(2027, 3, 15))
    m = result.metrics
    assert (m["verified_visits"], m["visits"], m["new_farmers"]) == (5, 8, 2)
    assert (m["sales_paise"], m["own_brand_share"]) == (80000, 0.25)
    assert m["cancelled_prior_sales_paise"] == 40000
    assert result.targets["sales_paise"] == 60000
    assert (result.gross_paise, result.clawback_paise, result.amount_paise) == (69900, 800, 69100)
    assert result.status == "preview" and result.rule_version == 1
    # VV-005 is the default; a rule that also counts partial visits pays for 7:
    # 2..4 at 100.00 + 4..7 at 150.00 = 650.00 -> (650 + 16 + 100) x 1.5 = 1149.00 - 8.00.
    wider = {**RULES, "eligibility": {"min_verified_visits": 2,
                                      "count_visit_statuses": ["verified", "partial"]}}  # fmt: skip
    rules = await active_rules(mini, wider)
    again = await service.preview(db_session, mini.tid, officer.id, MARCH, rules=rules)
    assert again.metrics["verified_visits"] == 7
    assert again.amount_paise == 114900 - 800


async def test_close_month_freezes_results(mini: Mini, db_session: AsyncSession) -> None:
    await march_activity(mini)
    officer = mini.user("o1")
    with pytest.raises(service.NoActiveRulesError):
        await service.close_month(
            db_session, tenant_id=mini.tid, month=MARCH, now=datetime(2027, 4, 1, 1, tzinfo=UTC)
        )
    await active_rules(mini)
    with pytest.raises(Exception, match="once it has ended"):
        await service.close_month(
            db_session, tenant_id=mini.tid, month=MARCH, now=ist(date(2027, 3, 31), 23)
        )
    report = await service.close_month(
        db_session, tenant_id=mini.tid, month=MARCH, now=datetime(2027, 4, 1, 1, tzinfo=UTC)
    )
    assert set(report.closed) == {officer.id, mini.user("o2").id}
    frozen = await service.preview(db_session, mini.tid, officer.id, MARCH)
    assert frozen.status == "closed" and frozen.amount_paise == 45800  # no target: no x1.5
    # New data for March after the close changes nothing; a re-run closes nothing new.
    await mini.visit("o1", "f1", ist(date(2027, 3, 30), 10), score=95)
    assert (await service.preview(db_session, mini.tid, officer.id, MARCH)).amount_paise == 45800
    rerun = await service.close_month(
        db_session, tenant_id=mini.tid, month=MARCH, now=datetime(2027, 4, 2, tzinfo=UTC)
    )
    assert rerun.closed == [] and rerun.already_closed == 2


async def test_incentive_for_port(mini: Mini, db_session: AsyncSession) -> None:
    officer = mini.user("o1")
    args = {"tenant_id": mini.tid, "officer_id": officer.id}
    none = await service.incentive_for(
        db_session, **args, period_start=MARCH, period_end=date(2027, 4, 1)
    )
    assert none is None  # no active rule set
    await march_activity(mini)
    await active_rules(mini)
    live = await service.incentive_for(
        db_session, **args, period_start=MARCH, period_end=date(2027, 3, 3)
    )
    assert live is not None and live.status == "preview"
    assert live.metrics["verified_visits"] == 2  # 1 and 2 March only
    await service.close_month(
        db_session, tenant_id=mini.tid, month=MARCH, now=datetime(2027, 4, 1, 1, tzinfo=UTC)
    )
    closed = await service.incentive_for(
        db_session,
        **args,
        period_start=datetime(2027, 2, 28, 18, 30, tzinfo=UTC),  # 1 March 00:00 IST
        period_end=date(2027, 4, 1),
    )
    assert closed is not None and closed.status == "closed" and closed.amount_paise == 45800
    stranger = await service.incentive_for(
        db_session,
        tenant_id=mini.tid,
        officer_id=uuid.uuid4(),
        period_start=MARCH,
        period_end=date(2027, 4, 1),
    )
    assert stranger is None


# --------------------------------------------------------------------------- API
async def test_rule_set_versions_and_preview_api(
    client: AsyncClient, mini: Mini, bearer: Bearer, step_up: Bearer
) -> None:
    await march_activity(mini)
    owner = headers(bearer, mini.user("owner"))
    bad = await client.post(
        "/v1/incentive-rules", json={"name": "x", "definition": {"components": []}}, headers=owner
    )
    assert bad.status_code == 422 and bad.json()["code"] == "invalid_incentive_rules"
    v1 = await client.post(
        "/v1/incentive-rules", json={"name": "v1", "definition": RULES}, headers=owner
    )
    assert v1.status_code == 201 and v1.json()["version"] == 1 and v1.json()["status"] == "draft"
    v2 = await client.post(
        "/v1/incentive-rules", json={"name": "v2", "definition": RULES, "activate": True},
        headers=owner,
    )  # fmt: skip
    assert v2.json()["version"] == 2 and v2.json()["status"] == "active"
    act = await client.post(f"/v1/incentive-rules/{v1.json()['id']}/activate", headers=owner)
    assert act.json()["status"] == "active"
    listed = await client.get("/v1/incentive-rules", headers=headers(bearer, mini.user("auditor")))
    assert [(r["version"], r["status"]) for r in listed.json()["items"]] == [
        (2, "retired"),
        (1, "active"),
    ]
    o1, o2 = mini.user("o1"), mini.user("o2")
    mine = await client.get(
        "/v1/incentives/preview", params={"month": "2027-03-01"}, headers=headers(bearer, o1)
    )
    assert mine.status_code == 200, mine.text
    assert mine.json()["amount_paise"] == 45800 and mine.json()["officer_id"] == str(o1.id)
    other = await client.get(
        "/v1/incentives/preview",
        params={"month": "2027-03-01", "officer_id": str(o2.id)},
        headers=headers(bearer, o1),
    )
    assert other.status_code == 404  # an officer sees only their own payout
    head = headers(bearer, mini.user("cluster_head"))  # North: O1, not O2 (South)
    ok = await client.get(
        "/v1/incentives/preview", params={"month": "2027-03-01", "officer_id": str(o1.id)},
        headers=head,
    )  # fmt: skip
    assert ok.status_code == 200
    south = await client.get(
        "/v1/incentives/preview", params={"month": "2027-03-01", "officer_id": str(o2.id)},
        headers=head,
    )  # fmt: skip
    assert south.status_code == 404
    draft = await client.post(
        "/v1/incentives/preview",
        json={
            "officer_id": str(o1.id),
            "month": "2027-03-01",
            "definition": {
                "components": [
                    {"id": "v", "metric": "verified_visits", "kind": "per_unit", "rate_paise": 100}
                ]
            },
        },
        headers=owner,
    )
    assert draft.status_code == 200 and draft.json()["amount_paise"] == 500
    no_step = await client.post("/v1/incentives/close", json={"month": "2027-03-01"}, headers=owner)
    assert no_step.status_code == 401 and no_step.json()["code"] == "step_up_required"
    early = await client.post(
        "/v1/incentives/close", json={"month": "2099-03-01"},
        headers=headers(bearer, mini.user("owner"), step_up),
    )  # fmt: skip
    assert early.status_code == 409 and early.json()["code"] == "incentive_month_open"
    closed = await client.post(
        "/v1/incentives/close", json={"month": "2026-08-01"},
        headers=headers(bearer, mini.user("owner"), step_up),
    )  # fmt: skip
    assert closed.status_code == 200 and closed.json()["closed"] == 2
    payouts = await client.get(
        "/v1/incentives/payouts", params={"month": "2026-08-15"}, headers=head
    )
    assert [p["officer_id"] for p in payouts.json()["items"]] == [str(o1.id)]


async def test_targets_api_scope(client: AsyncClient, mini: Mini, bearer: Bearer) -> None:
    head = headers(bearer, mini.user("cluster_head"))
    n1, s1 = mini.stores["N1"], mini.stores["S1"]
    body = {
        "month": "2027-03-10",
        "items": [
            {"subject_type": "store", "subject_id": str(n1.id), "sales_paise": 5_000_000},
            {"subject_type": "officer", "subject_id": str(mini.user("o1").id),
             "visits_verified": 60, "own_brand_share_bp": 4000},
        ],
    }  # fmt: skip
    put = await client.put("/v1/targets", json=body, headers=head)
    assert put.status_code == 200, put.text
    assert put.json()["month"] == "2027-03-01" and len(put.json()["items"]) == 2
    other = await client.put(
        "/v1/targets",
        json={
            "month": "2027-03-01",
            "items": [{"subject_type": "store", "subject_id": str(s1.id)}],
        },
        headers=head,
    )
    assert other.status_code == 404  # S1 is in the South cluster
    update = await client.put(
        "/v1/targets",
        json={"month": "2027-03-01", "items": [
            {"subject_type": "store", "subject_id": str(n1.id), "collections_paise": 100}]},
        headers=headers(bearer, mini.user("owner")),
    )  # fmt: skip
    assert update.status_code == 200, update.text
    assert update.json()["items"][0]["sales_paise"] == 5_000_000  # untouched keys kept
    manager = await client.get(
        "/v1/targets",
        params={"month": "2027-03-01"},
        headers=headers(bearer, mini.user("store_manager")),
    )
    assert {(t["subject_type"]) for t in manager.json()["items"]} == {"store", "officer"}
    officer = await client.get(
        "/v1/targets", params={"month": "2027-03-01"}, headers=headers(bearer, mini.user("o2"))
    )
    assert officer.json()["items"] == []
    denied = await client.put("/v1/targets", json=body, headers=headers(bearer, mini.user("o1")))
    assert denied.status_code == 403


def test_month_helpers() -> None:
    assert service.next_month(date(2027, 12, 5)) == date(2028, 1, 1)
    start, end = service.month_bounds(date(2027, 3, 9))
    assert start == datetime(2027, 2, 28, 18, 30, tzinfo=UTC)
    assert end - start == timedelta(days=31)
