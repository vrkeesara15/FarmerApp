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
      farmers: [{ref, name, village?, registered_by?, phone?, phone_verified?, at?, device?}]
      farms:   [{ref, farmer, area_acres, square: {east_m, north_m, side_m}}
                | {ref, farmer, area_acres, ring: [[east_m, north_m], ...]}]
    expect:
      flags: [{subject, owner?, watchers?, severity?, reasons?}]   # [] for a negative case

Times (``at``) are ``-<n>m`` / ``-<n>h`` / ``-<n>d`` relative to ``now``. Positions are
metres east / north of the village centre. ``device`` records the farmer's creation in the
audit trail with that ``X-Device-Id`` and the registering officer as the actor.
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

from farmerapp.auth.models import User, UserRole
from farmerapp.db import audit
from farmerapp.db.geo import offset, point_wkt, polygon_wkt
from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant
from farmerapp.farmers.models import Farm, Farmer
from farmerapp.flags.models import Flag
from farmerapp.rules.engine import RunReport, run_rules
from farmerapp.rules.loader import DEFAULT_RULES_DIR, RuleSet, load_rules
from farmerapp.rules.schema import Mode
from farmerapp.tenants.models import Cluster, Store, Village

FIXTURES_DIR = DEFAULT_RULES_DIR / "fixtures"
CASES = ("positive", "negative")
VILLAGE_LON, VILLAGE_LAT = 79.55, 18.02
DEFAULT_NOW = datetime(2026, 9, 18, 6, 30, tzinfo=UTC)  # 12:00 IST

_RELATIVE = re.compile(r"^-(\d+(?:\.\d+)?)([mhd])$")
_UNITS = {"m": "minutes", "h": "hours", "d": "days"}


def fixture_path(rule_id: str, case: str) -> Path:
    return FIXTURES_DIR / rule_id / f"{case}.yaml"


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


def assert_expected(world: BaseWorld, data: dict[str, Any], outcome: Outcome) -> None:
    expected = (data.get("expect") or {}).get("flags")
    assert expected is not None, "fixture needs expect.flags ([] for a negative case)"
    assert not outcome.report.failed, f"rule failed: {outcome.report.failed}"
    got = sorted((str(f.subject_id), f) for f in outcome.flags)
    assert len(outcome.flags) == len(expected), [f.title for f in outcome.flags]
    by_subject: dict[str, list[Flag]] = {}
    for key, flag in got:
        by_subject.setdefault(key, []).append(flag)
    for spec in expected:
        subject = str(world.refs[spec["subject"]])
        assert by_subject.get(subject), f"no flag about {spec['subject']}"
        flag = by_subject[subject].pop(0)
        if "owner" in spec:
            assert flag.owner_id == world.refs[spec["owner"]], (flag.owner_role, spec["owner"])
        if "watchers" in spec:
            assert sorted(map(str, flag.watchers)) == sorted(
                str(world.refs[w]) for w in spec["watchers"]
            )
        if "severity" in spec:
            assert flag.severity == spec["severity"]
        if "reasons" in spec:
            metrics = flag.evidence["metrics"]
            reasons = metrics.get("reasons") or [metrics.get("reason")]
            assert sorted(reasons) == sorted(spec["reasons"]), reasons
