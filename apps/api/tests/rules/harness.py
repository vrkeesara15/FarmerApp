"""Golden-fixture harness (VA-007): seed ``rules/fixtures/<rule>/<case>.yaml`` into a fresh
tenant, run the rule through the real engine, compare the flags with ``expect``.

Every fixture gets the same base world (``BaseWorld``): tenant, cluster ``c1``, store ``s1``
(in ``c1``), villages ``v1`` / ``v2`` (both served by ``s1``) and one active user per
reviewing role (``owner``, ``auditor``, ``cluster_head`` of ``c1``, ``store_manager`` of
``s1``) plus two field officers (``officer``, ``officer2``). A fixture adds records under
``seed``:

.. code-block:: yaml

    now: "2026-09-18T12:00:00+05:30"   # optional; the rule's clock
    mode: batch                        # inline | event | batch (default batch)
    trigger: farmer.registered         # event mode only
    subjects: [f2]                     # inline / event: the records the write touched
    seed:
      users:   [{ref, role, cluster?, store?}]
      farmers: [{ref, name, village?, registered_by?, phone?, phone_verified?, at?, captured?,
                 device?}]
      farms:   [{ref, farmer, area_acres, square: {east_m, north_m, side_m}}
                | {ref, farmer, area_acres, ring: [[east_m, north_m], ...]}]
      villages: [{ref, meeting_point: {east_m, north_m}, radius_m?}]   # edits v1 / v2
      farm_photos: [{ref, farm, sha256?, phash?, blob?}]
      duty:    [{ref, officer?, start, end?, integrity?: {is_mock, is_rooted, clock_drift_s}}]
      points:  [{duty, at, east_m, north_m, accuracy_m?, is_mock?, is_rooted?, clock_drift_s?}]
      visits:  [{ref, officer?, farmer, farm?, at, minutes?, east_m?, north_m?, geofence?,
                 purpose?, integrity?}]
      photos:  [{ref, visit, sha256?, phash?, flags?, exif?: {east_m, north_m}, blob?}]
      confirmations: [{ref, visit, channel, at, phone?, device?}]
    expect:
      flags: [{subject, owner?, watchers?, severity?, reasons?}]   # [] for a negative case

Times (``at``) are ``-<n>s`` / ``-<n>m`` / ``-<n>h`` / ``-<n>d`` relative to ``now``. Positions are
metres east / north of the village centre. ``device`` records the farmer's creation in the
audit trail with that ``X-Device-Id`` and the registering officer as the actor. ``at`` is the
server insert time (``created_at``); ``captured`` the device capture time of an offline
registration synced later (``captured_at``, same relative syntax).

Field data (M4 employee rules): ``duty`` sessions and their location ``points`` (the daily
``location_point`` partitions of the UTC days touched are created first), ``visits``
(``minutes`` = duration until check-out; omitted = still open), visit ``photos`` (hashes and
``photo_flags`` given directly), confirmations (``phone`` creates the OTP challenge the
code went to; ``device`` is ``confirmed_via_device_id``). Everything is relative to the
fixture's fixed ``now``: fixtures never depend on the wall clock.
"""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Any

import yaml
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import OtpChallenge, OtpPurpose, User, UserRole
from farmerapp.db import audit
from farmerapp.db.geo import offset, point_wkt, polygon_wkt
from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant
from farmerapp.farmers.models import Farm, Farmer, FarmPhoto
from farmerapp.flags.models import Flag
from farmerapp.location.models import DutySession, LocationPoint
from farmerapp.location.partitions import ensure_partitions
from farmerapp.rules.engine import RunReport, run_rules
from farmerapp.rules.loader import DEFAULT_RULES_DIR, RuleSet, load_rules
from farmerapp.rules.schema import Mode
from farmerapp.tenants.models import Cluster, Store, Village
from farmerapp.visits.models import (
    ConfirmationStatus,
    GeofenceResult,
    Visit,
    VisitConfirmation,
    VisitPhoto,
    VisitPurpose,
    VisitStatus,
)

FIXTURES_DIR = DEFAULT_RULES_DIR / "fixtures"
#: The eleven P0 rules of SPEC 6.2 / 6.3 (M4); VA-007 enforces a fixture pair for each.
P0_RULES = frozenset(
    {
        "VA-F01",
        "VA-F02",
        "VA-F03",
        "VA-F06",
        "VA-F08",
        "VA-E01",
        "VA-E02",
        "VA-E03",
        "VA-E04",
        "VA-E05",
        "VA-E08",
    }
)
CASES = ("positive", "negative")
VILLAGE_LON, VILLAGE_LAT = 79.55, 18.02
DEFAULT_NOW = datetime(2026, 9, 18, 6, 30, tzinfo=UTC)  # 12:00 IST

_RELATIVE = re.compile(r"^-(\d+(?:\.\d+)?)([smhd])$")
_UNITS = {"s": "seconds", "m": "minutes", "h": "hours", "d": "days"}


def fixture_path(rule_id: str, case: str) -> Path:
    return FIXTURES_DIR / rule_id / f"{case}.yaml"


def fixture_cases(rule_id: str) -> list[str]:
    """``positive`` and ``negative`` (required, VA-007) plus any extra scenario of the rule,
    ``positive-<name>.yaml`` / ``negative-<name>.yaml`` (e.g. VA-F08 ``positive-farm-photo``)."""
    extra = sorted(
        path.stem
        for path in (FIXTURES_DIR / rule_id).glob("*.yaml")
        if path.stem not in CASES and path.stem.startswith(tuple(f"{c}-" for c in CASES))
    )
    return [*CASES, *extra]


def case_sign(case: str) -> str:
    """``positive`` / ``negative`` of a fixture case name."""
    return case.split("-", 1)[0]


def load_fixture(rule_id: str, case: str) -> dict[str, Any]:
    data = yaml.safe_load(fixture_path(rule_id, case).read_text(encoding="utf-8"))
    assert isinstance(data, dict), f"{rule_id}/{case}.yaml must be a mapping"
    return data


def when(value: Any, now: datetime) -> datetime:
    if value is None:
        return now
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=UTC)
    match = _RELATIVE.match(str(value))
    if match:
        amount, unit = float(match.group(1)), _UNITS[match.group(2)]
        return now - timedelta(**{unit: amount})
    parsed = datetime.fromisoformat(str(value))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def _lonlat(east_m: float, north_m: float) -> tuple[float, float]:
    return offset(VILLAGE_LON, VILLAGE_LAT, float(east_m), float(north_m))


def _ring(spec: dict[str, Any]) -> list[tuple[float, float]]:
    if "square" in spec:
        sq = spec["square"]
        x, y, side = float(sq.get("east_m", 0)), float(sq.get("north_m", 0)), float(sq["side_m"])
        corners = [(x, y), (x + side, y), (x + side, y + side), (x, y + side)]
    else:
        corners = [(float(e), float(n)) for e, n in spec["ring"]]
    return [_lonlat(e, n) for e, n in corners]


@dataclass
class BaseWorld:
    tenant_id: uuid.UUID
    slug: str
    refs: dict[str, uuid.UUID] = field(default_factory=dict)
    users: dict[str, User] = field(default_factory=dict)

    def id(self, ref: str) -> uuid.UUID:
        return self.refs[ref]


_PHONE_SEQ = iter(range(10_000_000))


def _phone() -> str:
    return f"+9170{next(_PHONE_SEQ):08d}"


async def base_world(session: AsyncSession, *, slug: str | None = None) -> BaseWorld:
    """A fresh tenant with the reviewer roles; the session is left bound to it."""
    tid = uuid.uuid4()
    slug = slug or f"fx-{tid.hex[:10]}"
    await set_tenant(session, tid)
    session.add(Tenant(id=tid, name=f"Fixture {slug}", slug=slug))
    await session.flush()
    world = BaseWorld(tenant_id=tid, slug=slug)
    cluster = Cluster(tenant_id=tid, name="C1")
    session.add(cluster)
    await session.flush()
    store = Store(
        tenant_id=tid,
        code="S1",
        name="Store 1",
        cluster_id=cluster.id,
        district="Warangal",
        location=point_wkt(VILLAGE_LON, VILLAGE_LAT),
    )
    session.add(store)
    await session.flush()
    world.refs.update(c1=cluster.id, s1=store.id)
    for ref in ("v1", "v2"):
        village = Village(
            tenant_id=tid,
            name=f"Village {ref}",
            district="Warangal",
            mandal="Hasanparthy",
            store_id=store.id,
            location=point_wkt(VILLAGE_LON, VILLAGE_LAT),
        )
        session.add(village)
        await session.flush()
        world.refs[ref] = village.id
    for ref, role in (
        ("owner", UserRole.OWNER),
        ("auditor", UserRole.AUDITOR),
        ("cluster_head", UserRole.CLUSTER_HEAD),
        ("store_manager", UserRole.STORE_MANAGER),
        ("officer", UserRole.FIELD_OFFICER),
        ("officer2", UserRole.FIELD_OFFICER),
    ):
        await add_user(session, world, ref, role, cluster="c1", store="s1")
    return world


async def add_user(
    session: AsyncSession,
    world: BaseWorld,
    ref: str,
    role: UserRole | str,
    *,
    cluster: str | None = None,
    store: str | None = None,
    phone: str | None = None,
) -> User:
    role = UserRole(role)
    user = User(
        tenant_id=world.tenant_id,
        phone=phone or _phone(),
        name=ref.replace("_", " ").title(),
        role=role.value,
        cluster_id=world.refs[cluster] if cluster and role != UserRole.OWNER else None,
        store_id=world.refs[store]
        if store and role in (UserRole.STORE_MANAGER, UserRole.FIELD_OFFICER)
        else None,
    )
    session.add(user)
    await session.flush()
    world.refs[ref] = user.id
    world.users[ref] = user
    return user


async def add_farmer(
    session: AsyncSession, world: BaseWorld, spec: dict[str, Any], now: datetime
) -> Farmer:
    phone = str(spec.get("phone") or _phone())
    officer = spec.get("registered_by", "officer")
    at = when(spec.get("at"), now)
    farmer = Farmer(
        tenant_id=world.tenant_id,
        created_at=at,
        captured_at=when(spec["captured"], now) if spec.get("captured") else None,
        phone=phone,
        phone_last4=phone[-4:],
        name=str(spec.get("name", spec["ref"])),
        village_id=world.refs[spec.get("village", "v1")],
        registered_by=world.refs[officer] if officer else None,
        phone_verified=bool(spec.get("phone_verified", True)),
    )
    actor = audit.Actor(
        tenant_id=world.tenant_id,
        actor_id=world.refs[officer] if officer else None,
        actor_role=UserRole.FIELD_OFFICER.value,
        device_id=spec.get("device"),
    )
    with audit.actor_scope(actor):
        session.add(farmer)
        await session.flush()
    world.refs[spec["ref"]] = farmer.id
    return farmer


async def add_farm(session: AsyncSession, world: BaseWorld, spec: dict[str, Any]) -> Farm:
    ring = _ring(spec) if ("square" in spec or "ring" in spec) else None
    farm = Farm(
        tenant_id=world.tenant_id,
        farmer_id=world.refs[spec["farmer"]],
        name=spec.get("ref"),
        area_acres=Decimal(str(spec["area_acres"])),
        boundary=polygon_wkt(ring) if ring else None,
    )
    session.add(farm)
    await session.flush()
    world.refs[spec["ref"]] = farm.id
    return farm


def _point(spec: dict[str, Any]) -> str:
    return point_wkt(*_lonlat(spec.get("east_m", 0), spec.get("north_m", 0)))


async def edit_village(session: AsyncSession, world: BaseWorld, spec: dict[str, Any]) -> None:
    village = await session.get_one(Village, world.refs[spec["ref"]])
    meeting = spec.get("meeting_point")
    village.meeting_point = _point(meeting) if meeting else None
    village.meeting_point_radius_m = spec.get("radius_m")
    await session.flush()


async def add_farm_photo(session: AsyncSession, world: BaseWorld, spec: dict[str, Any]) -> None:
    photo = FarmPhoto(
        tenant_id=world.tenant_id,
        farm_id=world.refs[spec["farm"]],
        blob_uri=spec.get("blob") or f"gs://fixtures/{world.tenant_id}/farm/{spec['ref']}.jpg",
        sha256=spec.get("sha256"),
        phash=spec.get("phash"),
    )
    session.add(photo)
    await session.flush()
    world.refs[spec["ref"]] = photo.id


def _integrity(spec: dict[str, Any] | None) -> dict[str, Any]:
    spec = spec or {}
    return {
        "is_mock": bool(spec.get("is_mock", False)),
        "is_rooted": bool(spec.get("is_rooted", False)),
        "clock_drift_s": int(spec.get("clock_drift_s", 0)),
    }


async def add_duty(
    session: AsyncSession, world: BaseWorld, spec: dict[str, Any], now: datetime
) -> None:
    end = when(spec["end"], now) if spec.get("end") else None
    duty = DutySession(
        tenant_id=world.tenant_id,
        officer_id=world.refs[spec.get("officer", "officer")],
        start_at=when(spec.get("start"), now),
        end_at=end,
        end_reason="manual" if end is not None else None,
        start_point=_point(spec),
        policy_version="1",
        device_integrity=_integrity(spec.get("integrity")),
    )
    session.add(duty)
    await session.flush()
    world.refs[spec["ref"]] = duty.id


async def add_points(
    session: AsyncSession, world: BaseWorld, specs: list[dict[str, Any]], now: datetime
) -> None:
    """Location points; the UTC-day partitions they fall in are created first."""
    stamps = [when(s.get("at"), now) for s in specs]
    await ensure_partitions(
        session,
        from_day=min(stamps).astimezone(UTC).date(),
        to_day=max(stamps).astimezone(UTC).date(),
    )
    for spec, ts in zip(specs, stamps, strict=True):
        duty = await session.get_one(DutySession, world.refs[spec["duty"]])
        session.add(
            LocationPoint(
                tenant_id=world.tenant_id,
                officer_id=duty.officer_id,
                duty_session_id=duty.id,
                ts=ts,
                point=_point(spec),
                accuracy_m=float(spec.get("accuracy_m", 10)),
                is_mock=bool(spec.get("is_mock", False)),
                is_rooted=bool(spec.get("is_rooted", False)),
                clock_drift_s=int(spec.get("clock_drift_s", 0)),
                received_at=ts,
            )
        )
    await session.flush()


async def add_visit(
    session: AsyncSession, world: BaseWorld, spec: dict[str, Any], now: datetime
) -> None:
    checkin = when(spec.get("at"), now)
    minutes = spec.get("minutes")
    integrity = _integrity(spec.get("integrity"))
    issues = [
        name
        for name, bad in (
            ("mock_location", integrity["is_mock"]),
            ("rooted_device", integrity["is_rooted"]),
            ("clock_drift", abs(integrity["clock_drift_s"]) > 300),
        )
        if bad
    ]
    farm = spec.get("farm")
    visit = Visit(
        tenant_id=world.tenant_id,
        created_at=checkin,
        officer_id=world.refs[spec.get("officer", "officer")],
        farmer_id=world.refs[spec["farmer"]],
        farm_id=world.refs[farm] if farm else None,
        village_id=world.refs[spec.get("village", "v1")],
        purpose=VisitPurpose(spec.get("purpose", "advisory")).value,
        checkin_at=checkin,
        checkout_at=checkin + timedelta(minutes=float(minutes)) if minutes is not None else None,
        checkin_point=_point(spec),
        checkin_accuracy_m=8.0,
        geofence_result=GeofenceResult(spec.get("geofence", "inside")).value,
        override_note="fixture" if spec.get("geofence") == "override" else None,
        status=VisitStatus.OPEN.value,
        device_integrity={**integrity, "issues": issues},
        flags=[],
    )
    session.add(visit)
    await session.flush()
    world.refs[spec["ref"]] = visit.id


async def add_visit_photo(session: AsyncSession, world: BaseWorld, spec: dict[str, Any]) -> None:
    visit = await session.get_one(Visit, world.refs[spec["visit"]])
    exif = spec.get("exif")
    taken = visit.checkin_at + timedelta(minutes=2)
    photo = VisitPhoto(
        tenant_id=world.tenant_id,
        created_at=taken,
        visit_id=visit.id,
        blob_uri=spec.get("blob") or f"gs://fixtures/{world.tenant_id}/visit/{spec['ref']}.jpg",
        sha256=spec.get("sha256"),
        phash=str(spec["phash"]) if spec.get("phash") is not None else None,
        exif_time=taken,
        exif_point=_point(exif) if exif else None,
        taken_in_app=True,
        server_time=taken,
        photo_flags=list(spec.get("flags") or []),
    )
    session.add(photo)
    await session.flush()
    world.refs[spec["ref"]] = photo.id


async def add_confirmation(
    session: AsyncSession, world: BaseWorld, spec: dict[str, Any], now: datetime
) -> None:
    at = when(spec.get("at"), now)
    visit = await session.get_one(Visit, world.refs[spec["visit"]])
    phone = spec.get("phone")
    challenge_id = None
    if phone:
        challenge = OtpChallenge(
            tenant_id=world.tenant_id,
            phone=str(phone),
            purpose=OtpPurpose.FARMER_CONFIRM.value,
            code_hash="0" * 64,
            expires_at=at + timedelta(minutes=5),
            window_started_at=at,
            consumed_at=at,
        )
        session.add(challenge)
        await session.flush()
        challenge_id = challenge.id
    row = VisitConfirmation(
        tenant_id=world.tenant_id,
        created_at=at,
        visit_id=visit.id,
        channel=str(spec.get("channel", "sms_otp")),
        otp_challenge_id=challenge_id,
        farmer_phone_last4=str(phone)[-4:] if phone else None,
        status=ConfirmationStatus.CONFIRMED.value,
        requested_at=at,
        confirmed_at=at,
        confirmed_via_device_id=spec.get("device"),
    )
    session.add(row)
    visit.confirmation_channel = row.channel
    visit.confirmed_at = at
    await session.flush()
    world.refs[spec["ref"]] = row.id


async def seed(
    session: AsyncSession, world: BaseWorld, data: dict[str, Any], now: datetime
) -> None:
    records = data.get("seed") or {}
    for spec in records.get("users") or []:
        await add_user(
            session,
            world,
            spec["ref"],
            spec["role"],
            cluster=spec.get("cluster"),
            store=spec.get("store"),
            phone=spec.get("phone"),
        )
    for spec in records.get("farmers") or []:
        await add_farmer(session, world, spec, now)
    for spec in records.get("farms") or []:
        await add_farm(session, world, spec)
    for spec in records.get("villages") or []:
        await edit_village(session, world, spec)
    for spec in records.get("farm_photos") or []:
        await add_farm_photo(session, world, spec)
    for spec in records.get("duty") or []:
        await add_duty(session, world, spec, now)
    if records.get("points"):
        await add_points(session, world, records["points"], now)
    for spec in records.get("visits") or []:
        await add_visit(session, world, spec, now)
    for spec in records.get("photos") or []:
        await add_visit_photo(session, world, spec)
    for spec in records.get("confirmations") or []:
        await add_confirmation(session, world, spec, now)


@dataclass(frozen=True)
class Outcome:
    report: RunReport
    flags: list[Flag]


async def run_fixture(
    session: AsyncSession,
    rule_id: str,
    data: dict[str, Any],
    *,
    rule_set: RuleSet | None = None,
    world: BaseWorld | None = None,
) -> tuple[BaseWorld, Outcome]:
    now = when(data.get("now"), DEFAULT_NOW) if data.get("now") else DEFAULT_NOW
    world = world or await base_world(session)
    await seed(session, world, data, now)
    rule_set = rule_set or load_rules(DEFAULT_RULES_DIR)
    mode = Mode(data.get("mode", "batch"))
    subjects = [world.refs[r] for r in data.get("subjects") or []] or None
    report = await run_rules(
        session,
        world.tenant_id,
        mode,
        subject_ids=subjects if mode != Mode.BATCH else None,
        trigger=data.get("trigger"),
        rule_ids=[rule_id],
        now=now,
        rule_set=rule_set,
    )
    flags = (
        (
            await session.execute(
                select(Flag)
                .where(Flag.tenant_id == world.tenant_id, Flag.rule_id == rule_id)
                .order_by(Flag.created_at, Flag.id)
            )
        )
        .scalars()
        .all()
    )
    return world, Outcome(report=report, flags=list(flags))


def _reasons(flag: Flag) -> list[str]:
    metrics = flag.evidence["metrics"]
    return sorted(metrics.get("reasons") or [metrics.get("reason")])


def assert_expected(world: BaseWorld, data: dict[str, Any], outcome: Outcome) -> None:
    expected = (data.get("expect") or {}).get("flags")
    assert expected is not None, "fixture needs expect.flags ([] for a negative case)"
    assert not outcome.report.failed, f"rule failed: {outcome.report.failed}"
    assert len(outcome.flags) == len(expected), [f.title for f in outcome.flags]
    by_subject: dict[str, list[Flag]] = {}
    for flag in outcome.flags:
        by_subject.setdefault(str(flag.subject_id), []).append(flag)
    for spec in expected:
        subject = str(world.refs[spec["subject"]])
        candidates = by_subject.get(subject) or []
        assert candidates, f"no flag about {spec['subject']}"
        if "reasons" in spec:  # several flags about one subject: match them by reason
            matching = [f for f in candidates if _reasons(f) == sorted(spec["reasons"])]
            assert matching, [_reasons(f) for f in candidates]
            flag = matching[0]
        else:
            flag = candidates[0]
        candidates.remove(flag)
        if "owner" in spec:
            assert flag.owner_id == world.refs[spec["owner"]], (flag.owner_role, spec["owner"])
        if "watchers" in spec:
            assert sorted(map(str, flag.watchers)) == sorted(
                str(world.refs[w]) for w in spec["watchers"]
            )
        if "severity" in spec:
            assert flag.severity == spec["severity"]
