"""Demo seed (SPEC 10.5): two tenants with stores, officers, villages, farmers, farms, crop
plots and consent records; one user per role each (FA-001/002/003 fixtures).

* "Future Crop Care" (``fcc``, users ``+91900000000{1..10}``, officers ``+91900000001{1..4}``,
  farmers ``+919000100001..``) — the pilot tenant in Telangana: 2 clusters, 5 stores
  (Warangal, Karimnagar, Nalgonda, Khammam, Nizamabad), 5 field officers (one per store),
  40 villages, 200 farmers with 1-2 farms each (0.5-5 acre polygons around the village,
  non-overlapping), crop plots for the six pilot crops, consent records (data for all,
  marketing for ~60 %, a few withdrawn).
* "Green Fields" (``gfl``, users ``+91910000000{1..10}``) — 1 store (Raichur), 1 officer,
  10 farmers, so cross-tenant authorisation (SEC-006) and RLS (FA-003) tests have data on
  both sides.

Idempotent: every row has a stable id (``uuid5`` of the tenant id and a natural key) and the
seed only inserts what is missing (users are upserted by phone). Running it twice yields the
same counts. The data is generated from a fixed random seed, so it is the same on every
machine. ``SeedProfile`` scales the counts (``SMALL`` for the test fixtures, ``FULL`` for
``make seed``); the structure is identical.

Runs as the app role under RLS (FA-003): every demo tenant has a fixed id (uuid5 of its slug)
and is seeded inside its own ``tenant_scope``; writes are attributed to the system actor in
the audit trail (FA-006). Farms are inserted with ``eager_defaults``, so the database's
generated ``centroid`` / ``area_acres_computed`` come back in the same flush.
"""

from __future__ import annotations

import math
import random
import uuid
from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.catalog.crops import PILOT_CROPS, Crop
from farmerapp.db import audit
from farmerapp.db.base import Base
from farmerapp.db.geo import ACRE_M2, offset, point_wkt, polygon_wkt
from farmerapp.db.models import Tenant
from farmerapp.db.session import get_session_factory, tenant_scope
from farmerapp.farmers.models import (
    DEFAULT_CONSENT_VERSION,
    ConsentChannel,
    ConsentPurpose,
    ConsentRecord,
    ConsentSubject,
    CropPlot,
    CropStage,
    Farm,
    Farmer,
    FarmerSource,
    IrrigationType,
    LandOwnership,
    Season,
    SoilType,
)
from farmerapp.tenants.models import Cluster, Store, Village

DemoUser = tuple[str, str, UserRole, str]  # (phone, name, role, language)


TENANT_NAMESPACE = uuid.UUID("6f5b3d1e-0c2a-4b8e-9a7d-2f1e3c4b5a60")  # farmerapp demo tenants
RANDOM_SEED = 20260918
#: Fixed "today" so stages, sowing dates and consent timestamps are reproducible.
SEED_TODAY = date(2026, 9, 18)
CONSENT_VERSION = DEFAULT_CONSENT_VERSION  # TODO-LEGAL: placeholder (SPEC 14.6)


def demo_tenant_id(slug: str) -> uuid.UUID:
    """Stable id per demo tenant so the seed can bind its scope before the row exists."""
    return uuid.uuid5(TENANT_NAMESPACE, slug)


# --------------------------------------------------------------------------- definitions
@dataclass(frozen=True)
class DemoStore:
    code: str
    name: str
    district: str
    cluster: str
    lat: float
    lon: float
    villages: tuple[str, ...]  # mandal-headquarter villages of the district, nearest first
    state: str = "Telangana"


@dataclass(frozen=True)
class DemoOfficer:
    phone: str
    name: str
    language: str
    store_code: str


@dataclass(frozen=True)
class DemoTenant:
    name: str
    slug: str
    users: tuple[DemoUser, ...]
    clusters: tuple[str, ...] = ()
    stores: tuple[DemoStore, ...] = ()
    officers: tuple[DemoOfficer, ...] = ()  # extra field officers (the role user is one too)
    #: phone -> store code for role users that belong to a store (officer, store manager)
    placements: Mapping[str, str] = field(default_factory=dict)
    #: phone -> cluster name for cluster heads
    cluster_heads: Mapping[str, str] = field(default_factory=dict)
    farmer_phone_prefix: str = "+9190001"
    surnames: tuple[str, ...] = ()

    @property
    def id(self) -> uuid.UUID:
        return demo_tenant_id(self.slug)

    @property
    def all_users(self) -> tuple[DemoUser, ...]:
        return self.users + tuple(
            (o.phone, o.name, UserRole.FIELD_OFFICER, o.language) for o in self.officers
        )


@dataclass(frozen=True)
class SeedProfile:
    """How much to generate per tenant (structure is fixed, counts scale)."""

    farmers: Mapping[str, int]  # slug -> farmers
    villages_per_store: int


FULL = SeedProfile(farmers={"fcc": 200, "gfl": 10}, villages_per_store=8)
SMALL = SeedProfile(farmers={"fcc": 15, "gfl": 4}, villages_per_store=2)

DEMO_TENANT_NAME = "Future Crop Care"
DEMO_TENANT_SLUG = "fcc"

DEMO_USERS: tuple[DemoUser, ...] = (
    ("+919000000001", "Suresh Reddy", UserRole.OWNER, "en"),
    ("+919000000002", "Lakshmi Devi", UserRole.CLUSTER_HEAD, "te"),
    ("+919000000003", "Venkat Rao", UserRole.STORE_MANAGER, "te"),
    ("+919000000004", "Ramesh Kumar", UserRole.FIELD_OFFICER, "te"),
    ("+919000000005", "Dr. Anitha", UserRole.AGRONOMIST, "en"),
    ("+919000000006", "Prakash Reddy", UserRole.DIRECTOR, "en"),
    ("+919000000007", "Kavitha Rao", UserRole.AUDITOR, "en"),
    ("+919000000008", "Srinivas", UserRole.ACCOUNTANT, "te"),
    ("+919000000009", "Admin FCC", UserRole.TENANT_ADMIN, "en"),
    ("+919000000010", "Mallesh", UserRole.FARMER, "te"),
)

FCC_STORES: tuple[DemoStore, ...] = (
    DemoStore(
        "WGL", "FCC Warangal", "Warangal", "North Telangana", 17.9689, 79.5941,
        ("Hasanparthy", "Dharmasagar", "Geesugonda", "Sangem",
         "Atmakur", "Nallabelli", "Wardhannapet", "Parkal"),
    ),
    DemoStore(
        "KNR", "FCC Karimnagar", "Karimnagar", "North Telangana", 18.4386, 79.1288,
        ("Manakondur", "Choppadandi", "Gangadhara", "Ramadugu",
         "Thimmapur", "Saidapur", "Huzurabad", "Jammikunta"),
    ),
    DemoStore(
        "NLG", "FCC Nalgonda", "Nalgonda", "South Telangana", 17.0575, 79.2684,
        ("Kattangur", "Tipparthi", "Kanagal", "Narketpally",
         "Chityal", "Nakrekal", "Shaligouraram", "Miryalaguda"),
    ),
    DemoStore(
        "KMM", "FCC Khammam", "Khammam", "South Telangana", 17.2473, 80.1514,
        ("Raghunathapalem", "Mudigonda", "Konijerla", "Kusumanchi",
         "Nelakondapalli", "Chintakani", "Wyra", "Tallada"),
    ),
    DemoStore(
        "NZB", "FCC Nizamabad", "Nizamabad", "North Telangana", 18.6725, 78.0941,
        ("Dichpally", "Makloor", "Mupkal", "Sirikonda",
         "Yedapally", "Armoor", "Balkonda", "Bodhan"),
    ),
)  # fmt: skip

FCC_OFFICERS: tuple[DemoOfficer, ...] = (
    DemoOfficer("+919000000011", "Sathaiah Goud", "te", "KNR"),
    DemoOfficer("+919000000012", "Anjaneyulu", "te", "NLG"),
    DemoOfficer("+919000000013", "Bhaskar Naik", "te", "KMM"),
    DemoOfficer("+919000000014", "Rajender Yadav", "te", "NZB"),
)

GREEN_FIELDS_USERS: tuple[DemoUser, ...] = (
    ("+919100000001", "Manjunath Gowda", UserRole.OWNER, "en"),
    ("+919100000002", "Shanta Kumari", UserRole.CLUSTER_HEAD, "kn"),
    ("+919100000003", "Basavaraj", UserRole.STORE_MANAGER, "kn"),
    ("+919100000004", "Ravi Naik", UserRole.FIELD_OFFICER, "kn"),
    ("+919100000005", "Dr. Deepa", UserRole.AGRONOMIST, "en"),
    ("+919100000006", "Girish Gowda", UserRole.DIRECTOR, "en"),
    ("+919100000007", "Nagaraj", UserRole.AUDITOR, "en"),
    ("+919100000008", "Sunitha", UserRole.ACCOUNTANT, "kn"),
    ("+919100000009", "Admin GFL", UserRole.TENANT_ADMIN, "en"),
    ("+919100000010", "Siddappa", UserRole.FARMER, "kn"),
)

GFL_STORES: tuple[DemoStore, ...] = (
    DemoStore(
        "RCR", "Green Fields Raichur", "Raichur", "Raichur", 16.2076, 77.3463,
        ("Manvi", "Sirwar", "Kavital", "Maski", "Devadurga", "Lingsugur", "Mudgal", "Sindhanur"),
        state="Karnataka",
    ),
)  # fmt: skip

DEMO_TENANTS: tuple[DemoTenant, ...] = (
    DemoTenant(
        name=DEMO_TENANT_NAME,
        slug=DEMO_TENANT_SLUG,
        users=DEMO_USERS,
        clusters=("North Telangana", "South Telangana"),
        stores=FCC_STORES,
        officers=FCC_OFFICERS,
        placements={"+919000000003": "WGL", "+919000000004": "WGL"},
        cluster_heads={"+919000000002": "North Telangana"},
        farmer_phone_prefix="+9190001",
        surnames=("Reddy", "Goud", "Yadav", "Naik", "Mudiraj", "Rao", "Chary", "Nayak",
                  "Gangula", "Kummari", "Vemula", "Bandi", "Gaddam", "Puli", "Thota", "Kota"),
    ),
    DemoTenant(
        name="Green Fields",
        slug="gfl",
        users=GREEN_FIELDS_USERS,
        clusters=("Raichur",),
        stores=GFL_STORES,
        placements={"+919100000003": "RCR", "+919100000004": "RCR"},
        cluster_heads={"+919100000002": "Raichur"},
        farmer_phone_prefix="+9191001",
        surnames=("Gowda", "Patil", "Naik", "Reddy", "Shetty", "Kumar"),
    ),
)  # fmt: skip

GIVEN_NAMES_M = (
    "Ramesh", "Venkatesh", "Srinivas", "Narsimha", "Mallesh", "Rajender", "Yadagiri",
    "Sathaiah", "Anjaiah", "Bhaskar", "Lingaiah", "Komuraiah", "Sammaiah", "Ravinder",
    "Kishtaiah", "Mahender", "Nagaraju", "Prabhakar", "Sudhakar", "Ailaiah", "Pochaiah",
    "Chandraiah", "Balaiah", "Veeraiah", "Narender", "Yellaiah", "Ramulu", "Krishna",
    "Shankar", "Ganesh",
)  # fmt: skip
GIVEN_NAMES_F = (
    "Lakshmi", "Padma", "Swaroopa", "Anasuya", "Saraswathi", "Bhagyamma", "Rajamma",
    "Yellamma", "Laxmamma", "Sujatha", "Aruna", "Kavitha", "Manjula", "Vijaya", "Sarojini",
    "Radha", "Jyothi", "Mallamma", "Pochamma", "Sunitha",
)  # fmt: skip
LANDMARKS = (
    "near Hanuman temple", "opposite Gram Panchayat office", "beside the primary school",
    "next to the water tank", "near the bus stand", "behind the Rythu Vedika",
    "near the anganwadi", "near the check dam", "beside the cooperative society",
)  # fmt: skip
VARIETIES: Mapping[str, tuple[str, ...]] = {
    "paddy": ("BPT-5204 Samba Mahsuri", "MTU-1010", "RNR-15048 Telangana Sona", "JGL-24423"),
    "cotton": ("RCH-659 BG-II", "Jadoo BG-II", "Ajeet-155 BG-II", "Kaveri Money Maker"),
    "chilli": ("Teja LCA-334", "Guntur Sannam", "Byadgi", "US-341"),
    "maize": ("DHM-117", "Pioneer 30V92", "NK-6240", "DKC-9144"),
    "tomato": ("Arka Rakshak", "Heemsohna", "Abhilash", "Saaho"),
    "groundnut": ("K-6", "Kadiri Lepakshi", "TAG-24", "Dharani"),
}
#: Crops by season for the Telangana pilot districts (Rabi is mostly paddy/maize/groundnut).
KHARIF_CROPS = ("paddy", "cotton", "chilli", "maize", "tomato", "groundnut")
RABI_CROPS = ("paddy", "maize", "groundnut", "tomato")


# --------------------------------------------------------------------------- results
@dataclass(frozen=True)
class SeedResult:
    tenant_id: uuid.UUID  # the primary demo tenant (fcc)
    tenant_slug: str
    users_created: int  # across all demo tenants
    tenants: tuple[tuple[str, uuid.UUID], ...] = field(default_factory=tuple)
    #: rows inserted this run, per table, across all demo tenants
    created: Mapping[str, int] = field(default_factory=dict)
    #: rows present after the run, per table, across all demo tenants
    totals: Mapping[str, int] = field(default_factory=dict)


SEEDED_TABLES = ("cluster", "store", "village", "crop", "farmer", "farm", "crop_plot",
                 "consent_record")  # fmt: skip


# --------------------------------------------------------------------------- generation
def _sid(tenant: uuid.UUID, kind: str, key: str) -> uuid.UUID:
    """Stable id for a seeded row: the same input always yields the same uuid."""
    return uuid.uuid5(tenant, f"{kind}:{key}")


def _shoelace_m2(ring: list[tuple[float, float]]) -> float:
    area = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1], strict=True):
        area += x1 * y2 - x2 * y1
    return abs(area) / 2


class _FarmPlotter:
    """Lays farms out on a grid of cells around a village point so they never overlap.

    Cell ``k`` is at column ``k % 6``, row ``k // 6``, 240 m apart, starting 200 m east and
    150 m south of the village; each farm is a convex quadrilateral inside its own cell.
    """

    CELL_M = 240.0
    COLUMNS = 6
    MAX_SIDE_M = 220.0

    def __init__(self, rng: random.Random, lon: float, lat: float) -> None:
        self.rng, self.lon, self.lat, self.next_cell = rng, lon, lat, 0

    def farm(self, acres: float) -> tuple[str, float]:
        """(polygon EWKT, flat-earth area in acres) for a farm of about ``acres``."""
        cell, self.next_cell = self.next_cell, self.next_cell + 1
        col, row = cell % self.COLUMNS, cell // self.COLUMNS
        origin_e = 200.0 + col * self.CELL_M
        origin_n = -150.0 - row * self.CELL_M
        area_m2 = acres * ACRE_M2
        ratio = self.rng.uniform(0.6, 1.6)
        w = min(self.MAX_SIDE_M, math.sqrt(area_m2 * ratio))
        h = min(self.MAX_SIDE_M, area_m2 / w)
        # Corners of the rectangle pulled inward along their diagonal (stays convex).
        jitter = [(self.rng.uniform(0, 0.1) * w, self.rng.uniform(0, 0.1) * h) for _ in range(4)]
        corners_m = [
            (origin_e + jitter[0][0], origin_n + jitter[0][1]),
            (origin_e + w - jitter[1][0], origin_n + jitter[1][1]),
            (origin_e + w - jitter[2][0], origin_n + h - jitter[2][1]),
            (origin_e + jitter[3][0], origin_n + h - jitter[3][1]),
        ]
        ring = [offset(self.lon, self.lat, e, n) for e, n in corners_m]
        return polygon_wkt(ring), _shoelace_m2(corners_m) / ACRE_M2


def _stage(crop_days: int, sown: date, today: date) -> str:
    age = (today - sown).days
    if age >= crop_days:
        return CropStage.HARVESTED
    fraction = age / crop_days
    if fraction < 0.15:
        return CropStage.SOWN
    if fraction < 0.45:
        return CropStage.VEGETATIVE
    if fraction < 0.65:
        return CropStage.FLOWERING
    if fraction < 0.85:
        return CropStage.FRUITING
    return CropStage.MATURITY


@dataclass
class _Generated:
    """Everything the seed wants to exist for one tenant, keyed by table."""

    rows: dict[str, list[Any]] = field(default_factory=lambda: {t: [] for t in SEEDED_TABLES})

    def add(self, obj: Any) -> None:
        self.rows[obj.__tablename__].append(obj)


def _generate(
    demo: DemoTenant,
    profile: SeedProfile,
    users_by_phone: Mapping[str, User],
    rng: random.Random,
) -> _Generated:
    """Build the geography, master data and farmer graph for ``demo`` in memory."""
    tid = demo.id
    out = _Generated()

    clusters = {
        name: Cluster(id=_sid(tid, "cluster", name), tenant_id=tid, name=name, state="Telangana")
        for name in demo.clusters
    }
    for demo_store in demo.stores:
        clusters[demo_store.cluster].state = demo_store.state
    for cluster in clusters.values():
        out.add(cluster)

    crops: dict[str, Crop] = {}
    for code, name, names, duration in PILOT_CROPS:
        crops[code] = Crop(
            id=_sid(tid, "crop", code),
            tenant_id=tid,
            code=code,
            name=name,
            names=dict(names),
            duration_days=duration,
        )
        out.add(crops[code])

    stores: dict[str, Store] = {}
    villages: dict[str, list[Village]] = {}
    for demo_store in demo.stores:
        store = Store(
            id=_sid(tid, "store", demo_store.code),
            tenant_id=tid,
            code=demo_store.code,
            name=demo_store.name,
            cluster_id=clusters[demo_store.cluster].id,
            district=demo_store.district,
            state=demo_store.state,
            location=point_wkt(demo_store.lon, demo_store.lat),
        )
        stores[demo_store.code] = store
        out.add(store)
        villages[demo_store.code] = []
        for i, name in enumerate(demo_store.villages[: profile.villages_per_store]):
            bearing = math.radians(i * (360 / len(demo_store.villages)) + rng.uniform(-15, 15))
            distance = rng.uniform(6_000, 22_000)  # 6-22 km from the store
            lon, lat = offset(
                demo_store.lon,
                demo_store.lat,
                distance * math.sin(bearing),
                distance * math.cos(bearing),
            )
            meeting = offset(lon, lat, rng.uniform(-120, 120), rng.uniform(-120, 120))
            village = Village(
                id=_sid(tid, "village", f"{demo_store.district}/{name}"),
                tenant_id=tid,
                name=name,
                district=demo_store.district,
                mandal=name,
                state=demo_store.state,
                store_id=store.id,
                location=point_wkt(lon, lat),
                meeting_point=point_wkt(*meeting) if i % 2 == 0 else None,
            )
            villages[demo_store.code].append(village)
            out.add(village)

    # Officers per store: the role field officer plus the extra ones.
    officer_by_store: dict[str, User] = {}
    for placed_phone, placed_code in demo.placements.items():
        placed = users_by_phone[placed_phone]
        if placed.role == UserRole.FIELD_OFFICER:
            officer_by_store[placed_code] = placed
    for demo_officer in demo.officers:
        officer_by_store[demo_officer.store_code] = users_by_phone[demo_officer.phone]
    farmer_user = next(
        (users_by_phone[p] for p, _, role, _ in demo.users if role == UserRole.FARMER), None
    )

    total = profile.farmers.get(demo.slug, 0)
    store_codes = [s.code for s in demo.stores if s.code in officer_by_store]
    per_store = total // len(store_codes) if store_codes else 0
    plotters: dict[uuid.UUID, _FarmPlotter] = {}
    n = 0
    for code in store_codes:
        officer = officer_by_store[code]
        store_villages = villages[code]
        for i in range(per_store if code != store_codes[-1] else total - n):
            n += 1
            village = store_villages[i % len(store_villages)]
            phone = f"{demo.farmer_phone_prefix}{n:05d}"
            female = rng.random() < 0.25
            given = rng.choice(GIVEN_NAMES_F if female else GIVEN_NAMES_M)
            name = f"{given} {rng.choice(demo.surnames)}"
            user_id = None
            if n == 1 and farmer_user is not None:  # the demo farmer login owns farmer #1
                phone, name, user_id = farmer_user.phone, farmer_user.name, farmer_user.id
            registered_at = datetime.combine(
                SEED_TODAY - timedelta(days=rng.randint(1, 120)),
                datetime.min.time(),
                tzinfo=UTC,
            ) + timedelta(minutes=rng.randint(8 * 60, 18 * 60))
            marketing = rng.random() < 0.6
            withdrawn = marketing and rng.random() < 0.08
            farmer = Farmer(
                id=_sid(tid, "farmer", phone),
                tenant_id=tid,
                phone=phone,
                phone_last4=Farmer.last4(phone),
                name=name,
                village_id=village.id,
                landmark=rng.choice(LANDMARKS),
                language="kn" if demo.slug == "gfl" else "te",
                consent_marketing=marketing and not withdrawn,
                consent_version=CONSENT_VERSION,
                registered_by=officer.id,
                user_id=user_id,
                source=FarmerSource.OFFICER,
                land_ownership=rng.choice(
                    (LandOwnership.OWN, LandOwnership.OWN, LandOwnership.LEASED)
                ),
                created_at=registered_at,
                updated_at=registered_at,
            )
            out.add(farmer)

            plotter = plotters.setdefault(
                village.id, _FarmPlotter(rng, *_lon_lat(village.location))
            )
            for f in range(1 if rng.random() < 0.6 else 2):
                wkt, acres = plotter.farm(rng.uniform(0.5, 5.0))
                declared = round(acres * rng.uniform(0.93, 1.07), 2)
                farm = Farm(
                    id=_sid(tid, "farm", f"{phone}/{f + 1}"),
                    tenant_id=tid,
                    farmer_id=farmer.id,
                    name=f"Farm {f + 1}",
                    survey_no=str(rng.randint(10, 999)),
                    boundary=wkt,
                    area_acres=Decimal(str(max(declared, 0.5))),
                    soil=rng.choice(list(SoilType)),
                    irrigation=rng.choice(list(IrrigationType)),
                    ownership=(
                        LandOwnership.LEASED
                        if farmer.land_ownership == LandOwnership.LEASED
                        else LandOwnership.OWN
                    ),
                    created_at=registered_at,
                    updated_at=registered_at,
                )
                out.add(farm)
                plots = 1 if rng.random() < 0.55 else 2
                for p in range(plots):
                    season: Season
                    code_choices: tuple[str, ...]
                    if rng.random() < 0.75:
                        season, code_choices = Season.KHARIF, KHARIF_CROPS
                        sown = date(2026, 6, 10) + timedelta(days=rng.randint(0, 45))
                    else:
                        season, code_choices = Season.RABI, RABI_CROPS
                        sown = date(2025, 11, 1) + timedelta(days=rng.randint(0, 45))
                    crop = crops[rng.choice(code_choices)]
                    duration = crop.duration_days or 120
                    out.add(
                        CropPlot(
                            id=_sid(tid, "crop_plot", f"{phone}/{f + 1}/{p + 1}"),
                            tenant_id=tid,
                            farm_id=farm.id,
                            crop_id=crop.id,
                            variety=rng.choice(VARIETIES[crop.code]),
                            season=season,
                            sowing_date=sown,
                            stage=_stage(duration, sown, SEED_TODAY),
                            expected_harvest=sown + timedelta(days=duration),
                            area_acres=(
                                farm.area_acres
                                if plots == 1
                                else (farm.area_acres / 2).quantize(Decimal("0.01"))
                            ),
                            created_at=registered_at,
                            updated_at=registered_at,
                        )
                    )

            out.add(_consent(farmer, officer, ConsentPurpose.DATA, granted_at=registered_at))
            if marketing:
                out.add(
                    _consent(farmer, officer, ConsentPurpose.MARKETING, granted_at=registered_at)
                )
            if withdrawn:
                later = registered_at + timedelta(days=rng.randint(5, 40))
                out.add(_consent(farmer, officer, ConsentPurpose.MARKETING, withdrawn_at=later))
    return out


def _consent(
    farmer: Farmer,
    officer: User,
    purpose: str,
    *,
    granted_at: datetime | None = None,
    withdrawn_at: datetime | None = None,
) -> ConsentRecord:
    """A grant (``granted_at``) or a withdrawal (``withdrawn_at``) row for ``farmer``."""
    key = "withdraw" if withdrawn_at is not None else "grant"
    when = withdrawn_at or granted_at
    if when is None:
        raise ValueError("a consent record is either a grant or a withdrawal")
    return ConsentRecord(
        id=_sid(farmer.tenant_id, "consent_record", f"{farmer.phone}/{purpose}/{key}"),
        tenant_id=farmer.tenant_id,
        subject_type=ConsentSubject.FARMER,
        subject_id=farmer.id,
        purpose=purpose,
        version=CONSENT_VERSION,
        language=farmer.language,
        granted_at=granted_at,
        withdrawn_at=withdrawn_at,
        channel=ConsentChannel.OFFICER,
        recorded_by=officer.id,
        created_at=when,
    )


def _lon_lat(point_ewkt: str) -> tuple[float, float]:
    inner = point_ewkt[point_ewkt.index("(") + 1 : point_ewkt.index(")")]
    lon, lat = inner.split()
    return float(lon), float(lat)


# --------------------------------------------------------------------------- persistence
async def _seed_users(
    session: AsyncSession, demo: DemoTenant, tenant: Tenant
) -> tuple[dict[str, User], int]:
    existing = {
        u.phone: u
        for u in (await session.execute(select(User).where(User.tenant_id == tenant.id))).scalars()
    }
    created = 0
    for phone, name, role, language in demo.all_users:
        user = existing.get(phone)
        if user is None:
            user = User(
                id=_sid(tenant.id, "user", phone),
                tenant_id=tenant.id,
                phone=phone,
                name=name,
                role=role,
                language=language,
                status=UserStatus.ACTIVE,
            )
            session.add(user)
            existing[phone] = user
            created += 1
        else:
            user.name, user.role, user.language = name, role, language
    # Store / cluster placement (idempotent: set to the seeded value).
    store_ids = {s.code: _sid(tenant.id, "store", s.code) for s in demo.stores}
    cluster_ids = {name: _sid(tenant.id, "cluster", name) for name in demo.clusters}
    store_cluster = {s.code: cluster_ids[s.cluster] for s in demo.stores}
    for phone, code in demo.placements.items():
        existing[phone].store_id = store_ids[code]
        existing[phone].cluster_id = store_cluster[code]
    for officer in demo.officers:
        existing[officer.phone].store_id = store_ids[officer.store_code]
        existing[officer.phone].cluster_id = store_cluster[officer.store_code]
    for phone, name in demo.cluster_heads.items():
        existing[phone].cluster_id = cluster_ids[name]
    await session.flush()
    return existing, created


async def _existing_ids(session: AsyncSession, tenant_id: uuid.UUID) -> dict[str, set[uuid.UUID]]:
    ids: dict[str, set[uuid.UUID]] = {}
    for table in SEEDED_TABLES:
        model = Base.metadata.tables[table]
        rows = await session.execute(select(model.c.id).where(model.c.tenant_id == tenant_id))
        ids[table] = {r[0] for r in rows}
    return ids


async def _seed_tenant(
    session: AsyncSession, demo: DemoTenant, profile: SeedProfile, rng: random.Random
) -> tuple[Tenant, int, dict[str, int], dict[str, int]]:
    tenant = await session.get(Tenant, demo.id)
    if tenant is None:
        tenant = Tenant(id=demo.id, name=demo.name, slug=demo.slug)
        session.add(tenant)
        await session.flush()
    elif tenant.name != demo.name:
        tenant.name = demo.name

    users, users_created = await _seed_users(session, demo, tenant)
    generated = _generate(demo, profile, users, rng)
    existing = await _existing_ids(session, tenant.id)
    created: dict[str, int] = {}
    totals: dict[str, int] = {}
    for table in SEEDED_TABLES:  # dependency order; one flush per table (no relationships)
        missing = [row for row in generated.rows[table] if row.id not in existing[table]]
        session.add_all(missing)
        await session.flush()
        created[table] = len(missing)
        totals[table] = len(existing[table] | {row.id for row in generated.rows[table]})
    return tenant, users_created, created, totals


async def seed_demo(session: AsyncSession, profile: SeedProfile = FULL) -> SeedResult:
    seeded: list[tuple[str, uuid.UUID]] = []
    users_created = 0
    created: dict[str, int] = dict.fromkeys(SEEDED_TABLES, 0)
    totals: dict[str, int] = dict.fromkeys(SEEDED_TABLES, 0)
    for demo in DEMO_TENANTS:
        # Reproducible demo data, not a security context (bandit B311).
        rng = random.Random(f"{RANDOM_SEED}:{demo.slug}")  # nosec B311
        with audit.actor_scope(audit.system_actor(demo.id)):
            async with tenant_scope(session, demo.id):
                tenant, n, c, t = await _seed_tenant(session, demo, profile, rng)
        seeded.append((demo.slug, tenant.id))
        users_created += n
        for table in SEEDED_TABLES:
            created[table] += c[table]
            totals[table] += t[table]
    primary = dict(seeded)[DEMO_TENANT_SLUG]
    return SeedResult(
        tenant_id=primary,
        tenant_slug=DEMO_TENANT_SLUG,
        users_created=users_created,
        tenants=tuple(seeded),
        created=created,
        totals=totals,
    )


async def run_seed(profile: SeedProfile = FULL) -> SeedResult:
    factory = get_session_factory()
    async with factory() as session, session.begin():
        return await seed_demo(session, profile)
