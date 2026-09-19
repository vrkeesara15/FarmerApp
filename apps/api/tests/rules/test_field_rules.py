"""M4 employee / photo rules beyond the golden fixtures: thresholds are YAML params (VA-001) —
tuning one flips the negative fixture —, the tenant's minimum visit duration drives VA-E04,
VA-F08 matches farm photos by bytes, and the Pub/Sub worker runs the ``location.batch`` /
``visit.created`` / ``duty.started`` rules idempotently."""

from __future__ import annotations

import base64
import contextlib
import json
import uuid
from collections.abc import AsyncIterator
from dataclasses import replace
from typing import Any

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.models import Tenant
from farmerapp.db.session import tenant_scope
from farmerapp.flags.models import Flag
from farmerapp.rules import events
from farmerapp.rules.checks.va_e02 import _Fix, fast_legs
from farmerapp.rules.checks.va_e03 import _Visit, clusters
from farmerapp.rules.engine import run_rules
from farmerapp.rules.loader import DEFAULT_RULES_DIR, RuleSet, load_rules
from farmerapp.rules.schema import Mode
from farmerapp.worker.messages import PubSubMessage
from tests.rules.harness import (
    DEFAULT_NOW,
    BaseWorld,
    assert_expected,
    base_world,
    load_fixture,
    run_fixture,
    seed,
)

RULES = load_rules(DEFAULT_RULES_DIR)


def tuned(rule_id: str, **params: Any) -> RuleSet:
    """The repository rules with some params of one rule changed (a YAML-only change)."""
    config = RULES.get(rule_id)
    changed = config.model_copy(update={"params": {**config.params, **params}})
    return replace(RULES, rules={**RULES.rules, rule_id: changed})


def _reasons(flag: Flag) -> list[str]:
    metrics = flag.evidence["metrics"]
    return sorted(metrics.get("reasons") or [metrics["reason"]])


@pytest.fixture
async def world(db_session: AsyncSession) -> BaseWorld:
    return await base_world(db_session)


# --------------------------------------------------------------------------- VA-001 tuning
@pytest.mark.parametrize(
    ("rule_id", "params", "subject", "reasons"),
    [
        ("VA-F08", {"max_hamming_distance": 16}, "f2", ["photo_reuse"]),
        ("VA-E02", {"max_accuracy_m": 1000}, "officer", ["impossible_travel"]),
        ("VA-E03", {"min_farms": 4}, "officer2", ["clustered_visits"]),
        ("VA-E04", {"max_short_share": 0.3}, "officer", ["short_visits"]),
        ("VA-E05", {"window_days": 9}, "officer", ["same_otp_phone"]),
        ("VA-E05", {"min_farmers_per_device": 2}, "officer2", ["same_confirm_device"]),
        (
            "VA-E08",
            {"flag_missing_exif": True},
            "officer",
            ["exif_gps_missing", "exif_time_missing"],
        ),
    ],
)
async def test_a_yaml_threshold_change_flips_the_negative_fixture(
    db_session: AsyncSession,
    rule_id: str,
    params: dict[str, Any],
    subject: str,
    reasons: list[str],
) -> None:
    data = load_fixture(rule_id, "negative")
    world, outcome = await run_fixture(db_session, rule_id, data, rule_set=tuned(rule_id, **params))
    assert [(f.subject_id, _reasons(f)) for f in outcome.flags] == [(world.refs[subject], reasons)]


async def test_e01_duty_start_signal(db_session: AsyncSession) -> None:
    data = {
        "mode": "event",
        "trigger": "duty.started",
        "subjects": ["d1"],
        "seed": {
            "duty": [
                {"ref": "d1", "start": "-1h", "integrity": {"is_rooted": True, "clock_drift_s": 30}}
            ]
        },
        "expect": {
            "flags": [
                {
                    "subject": "officer",
                    "owner": "cluster_head",
                    "watchers": ["auditor"],
                    "reasons": ["rooted_device"],
                }
            ]
        },
    }
    world, outcome = await run_fixture(db_session, "VA-E01", data, rule_set=RULES)
    assert_expected(world, data, outcome)
    records = {(r["type"], r["id"]) for r in outcome.flags[0].evidence["records"]}
    assert ("duty_session", str(world.refs["d1"])) in records


async def test_e04_follows_the_tenant_minimum_duration(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    tenant = await db_session.get_one(Tenant, world.tenant_id)
    tenant.settings = {**(tenant.settings or {}), "min_visit_duration_s": 301}
    await db_session.flush()
    data = load_fixture("VA-E04", "negative")  # the 5-minute visit is now short: 3 of 5
    _world, outcome = await run_fixture(db_session, "VA-E04", data, rule_set=RULES, world=world)
    assert [f.subject_id for f in outcome.flags] == [world.refs["officer"]]
    assert outcome.flags[0].evidence["metrics"]["min_visit_duration_s"] == 301


async def test_f08_matches_farm_photos_by_bytes(db_session: AsyncSession) -> None:
    same = "9" * 64
    data = {
        "mode": "event",
        "trigger": "farm.photo",
        "subjects": ["farm2"],
        "seed": {
            "farmers": [{"ref": "f1", "at": "-30d"}, {"ref": "f2", "at": "-1d"}],
            "farms": [
                {"ref": "farm1", "farmer": "f1", "area_acres": 1.0},
                {"ref": "farm2", "farmer": "f2", "area_acres": 1.0},
            ],
            "visits": [{"ref": "visit1", "farmer": "f1", "at": "-5d", "minutes": 20}],
            "photos": [
                {"ref": "p1", "visit": "visit1", "sha256": same, "phash": "00ff00ff00ff00ff"}
            ],
            "farm_photos": [
                {"ref": "fp1", "farm": "farm1", "sha256": same},
                {"ref": "fp2", "farm": "farm2", "sha256": same},
                {"ref": "fp3", "farm": "farm2", "sha256": "a" * 64},
            ],
        },
        "expect": {
            "flags": [
                {"subject": "f2", "owner": "store_manager", "watchers": ["auditor"]},
                {"subject": "f2", "owner": "store_manager", "watchers": ["auditor"]},
            ]
        },
    }
    world, outcome = await run_fixture(db_session, "VA-F08", data, rule_set=RULES)
    assert_expected(world, data, outcome)
    matched = sorted(
        next(r["id"] for r in f.evidence["records"][3:] if r["type"] != "farmer")
        for f in outcome.flags
    )
    assert matched == sorted([str(world.refs["fp1"]), str(world.refs["p1"])])
    for flag in outcome.flags:
        metrics = flag.evidence["metrics"]
        assert metrics["hamming_distance"] == 0 and metrics["match"] == "sha256"
        assert metrics["other_farmer_id"] == str(world.refs["f1"])
        assert len(flag.evidence["photos"]) == 2

    # max_matches_per_photo caps the pairs raised for one new photo
    _w, capped = await run_fixture(
        db_session,
        "VA-F08",
        {**data, "subjects": ["farm2"]},
        rule_set=tuned("VA-F08", max_matches_per_photo=1),
    )
    assert len(capped.flags) == 1


async def test_event_rules_need_the_event_subjects(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    """Event-only rules never scan the whole tenant (a subject-less run finds nothing)."""
    report = await run_rules(
        db_session,
        world.tenant_id,
        Mode.EVENT,
        trigger="location.batch",
        subject_ids=None,
        rule_set=RULES,
        now=DEFAULT_NOW,
    )
    assert sorted(report.rules_run) == ["VA-E01", "VA-E02"] and report.total_raised == 0
    for trigger in ("visit.photo", "farm.photo"):
        report = await run_rules(
            db_session, world.tenant_id, Mode.EVENT, trigger=trigger, rule_set=RULES
        )
        assert report.total_raised == 0 and not report.failed


# --------------------------------------------------------------------------- pure helpers
def test_fast_legs_filters_accuracy_and_jitter() -> None:
    t0 = DEFAULT_NOW
    officer = uuid.uuid4()

    def fix(seconds: float, lon: float, accuracy: float = 5.0) -> _Fix:
        from datetime import timedelta

        return _Fix(uuid.uuid4(), officer, t0 + timedelta(seconds=seconds), lon, 18.0, accuracy)

    # same timestamp twice: skipped; 0.01 deg lon ~ 1 km in 10 s: fast
    legs = fast_legs(
        [fix(0, 79.0), fix(0, 79.001), fix(10, 79.011)], max_speed_kmh=90, max_accuracy_m=100
    )
    assert len(legs) == 1 and legs[0].speed_kmh > 300
    assert (
        fast_legs([fix(0, 79.0), fix(10, 79.011, 500)], max_speed_kmh=90, max_accuracy_m=100) == []
    )


def test_clusters_are_cliques_not_chains() -> None:
    officer = uuid.uuid4()
    # a chain of points 150 m apart: neighbours within 200 m, but the ends are 300 m apart
    step = 150 / 111_320 / 0.951  # metres -> degrees of longitude at 18 deg N (approx)
    chain = [
        _Visit(uuid.uuid4(), officer, uuid.uuid4(), 79.0 + i * step, 18.0, "2026-09-18")
        for i in range(3)
    ]
    assert max(len(c) for c in clusters(chain, 200)) == 2


# --------------------------------------------------------------------------- worker
def _message(payload: dict[str, Any]) -> PubSubMessage:
    return PubSubMessage(
        data=base64.b64encode(json.dumps(payload).encode()).decode(), messageId="m"
    )


def _provider(session: AsyncSession) -> Any:
    @contextlib.asynccontextmanager
    async def provide(tenant_id: uuid.UUID) -> AsyncIterator[AsyncSession]:
        async with tenant_scope(session, tenant_id):
            yield session

    return provide


async def _flags(session: AsyncSession, world: BaseWorld, rule_id: str) -> list[Flag]:
    rows = await session.execute(
        select(Flag).where(Flag.tenant_id == world.tenant_id, Flag.rule_id == rule_id)
    )
    return list(rows.scalars())


async def test_worker_runs_location_batch_rules(db_session: AsyncSession, world: BaseWorld) -> None:
    data = load_fixture("VA-E02", "positive")
    await seed(db_session, world, data, DEFAULT_NOW)
    msg = _message({"tenant_id": str(world.tenant_id), "duty_session_id": str(world.refs["d1"])})
    kwargs: dict[str, Any] = {
        "session_provider": _provider(db_session),
        "rule_set": RULES,
        "now": DEFAULT_NOW,
    }
    report = await events.handle_event_message("location.batch", msg, **kwargs)
    assert report is not None and report.raised["VA-E02"] == 1
    assert sorted(report.rules_run) == ["VA-E01", "VA-E02"]
    again = await events.handle_event_message("location.batch", msg, **kwargs)
    assert again is not None and again.total_raised == 0  # redelivery is a no-op
    [flag] = await _flags(db_session, world, "VA-E02")
    assert flag.raised_by_mode == "event" and flag.owner_id == world.refs["cluster_head"]
    assert len(flag.evidence["map"]["points"]) == 2
    assert flag.evidence["metrics"]["speed_kmh"] > 90


async def test_worker_runs_visit_created_rules(db_session: AsyncSession, world: BaseWorld) -> None:
    data = load_fixture("VA-E01", "positive")
    await seed(db_session, world, data, DEFAULT_NOW)
    msg = _message({"tenant_id": str(world.tenant_id), "visit_id": str(world.refs["visit1"])})
    report = await events.handle_event_message(
        "visit.created",
        msg,
        session_provider=_provider(db_session),
        rule_set=RULES,
        now=DEFAULT_NOW,
    )
    assert report is not None and report.raised["VA-E01"] == 1
    [flag] = await _flags(db_session, world, "VA-E01")
    assert _reasons(flag) == ["clock_drift", "mock_location", "rooted_device"]
    assert flag.dedupe_key.endswith(":integrity:2026-09-18")
