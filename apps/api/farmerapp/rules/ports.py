"""Ports the M7 rules read data through when the data lives outside the rules' reach.

Three checks depend on data that does not exist yet in this milestone, or not in the
database at all. Each reads it through a small protocol with a *null* adapter (the default:
no rows, so the rule raises nothing) and an *in-memory* adapter (tests and golden fixtures):

* ``SegmentMembershipPort`` — VA-F09: which farmers are in a campaign segment. Campaigns
  arrive with WC-008; until they register their adapter (``set_ports(segments=...)`` at
  startup) the null adapter returns no members.
* ``TravelClaimPort`` — VA-E07: submitted TA claims (FA-023). The travel package registers
  its adapter and calls ``farmerapp.rules.events.on_travel_claim_submitted`` (or publishes
  ``ta.claim.submitted``) when a claim is submitted.
* ``LandCoverPort`` — VA-F04: the land-cover class under a farm (road / water / built-up).
  **Human gate**: a real dataset (e.g. ESA WorldCover 10 m, plus OSM roads) loaded into
  PostGIS and a ``PostgisLandCoverPort`` over it (docs/prs/M7-rules.md). Until then the null
  adapter classifies nothing and only the service-district half of VA-F04 runs.

Adapters are process-wide (``get_ports()``); ``override_ports(...)`` swaps them for a block
(tests, fixtures). Every adapter method receives the rule's session (bound to the tenant
under RLS) and the tenant id, so an adapter never reads another tenant's rows.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass, field, replace
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession


# --------------------------------------------------------------------------- VA-F09 segments
@dataclass(frozen=True)
class SegmentMember:
    tenant_id: uuid.UUID
    farmer_id: uuid.UUID
    segment_id: str
    campaign_id: str | None = None


class SegmentMembershipPort(Protocol):
    async def members(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        farmer_ids: Sequence[uuid.UUID] | None = None,
    ) -> list[SegmentMember]:
        """Current members of the tenant's campaign segments (optionally only these
        farmers)."""
        ...


class NoSegments:
    """Until WC-008 campaigns exist: nobody is in a segment."""

    async def members(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        farmer_ids: Sequence[uuid.UUID] | None = None,
    ) -> list[SegmentMember]:
        return []


@dataclass
class InMemorySegments:
    rows: list[SegmentMember] = field(default_factory=list)

    async def members(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        farmer_ids: Sequence[uuid.UUID] | None = None,
    ) -> list[SegmentMember]:
        wanted = set(farmer_ids) if farmer_ids is not None else None
        return [
            r
            for r in self.rows
            if r.tenant_id == tenant_id and (wanted is None or r.farmer_id in wanted)
        ]


# --------------------------------------------------------------------------- VA-E07 TA claims
@dataclass(frozen=True)
class TravelClaim:
    """A submitted travel-allowance claim (FA-023): the officer, the IST day, the kind of
    claim, the km claimed and, when the app sent them, the duty sessions it covers.

    ``claim_type`` is the FA-023 type (``fuel`` / ``bus`` / ``other``; a tenant may add
    ``own_vehicle``). VA-E07 only compares a *vehicle* claim with the computed km: a fare
    (bus and the like) pays for a ticket, not for the distance the officer drove, so it says
    nothing about the track."""

    tenant_id: uuid.UUID
    id: uuid.UUID
    officer_id: uuid.UUID
    day: date
    claimed_km: Decimal
    submitted_at: datetime
    duty_session_ids: tuple[uuid.UUID, ...] = ()
    claim_type: str = "fuel"


class TravelClaimPort(Protocol):
    async def claims(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        *,
        claim_ids: Sequence[uuid.UUID] | None = None,
        submitted_since: datetime | None = None,
    ) -> list[TravelClaim]: ...


class NoTravelClaims:
    """Until FA-023 registers its adapter: no claims."""

    async def claims(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        *,
        claim_ids: Sequence[uuid.UUID] | None = None,
        submitted_since: datetime | None = None,
    ) -> list[TravelClaim]:
        return []


@dataclass
class InMemoryTravelClaims:
    rows: list[TravelClaim] = field(default_factory=list)

    async def claims(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        *,
        claim_ids: Sequence[uuid.UUID] | None = None,
        submitted_since: datetime | None = None,
    ) -> list[TravelClaim]:
        wanted = set(claim_ids) if claim_ids is not None else None
        return [
            c
            for c in self.rows
            if c.tenant_id == tenant_id
            and (wanted is None or c.id in wanted)
            and (submitted_since is None or c.submitted_at >= submitted_since)
        ]


# --------------------------------------------------------------------------- VA-F04 land cover
class LandCover(StrEnum):
    """Classes the VA-F04 check cares about (ESA WorldCover maps built-up and water; roads
    come from a road layer)."""

    CROPLAND = "cropland"
    TREE_COVER = "tree_cover"
    GRASSLAND = "grassland"
    BARE = "bare"
    BUILT_UP = "built_up"
    WATER = "water"
    ROAD = "road"
    UNKNOWN = "unknown"


#: A farm on one of these is implausible (SPEC 6.2 VA-F04).
IMPLAUSIBLE_COVER = frozenset({LandCover.BUILT_UP, LandCover.WATER, LandCover.ROAD})


@dataclass(frozen=True)
class FarmLocation:
    farm_id: uuid.UUID
    lon: float
    lat: float


class LandCoverPort(Protocol):
    async def classify(
        self, session: AsyncSession, tenant_id: uuid.UUID, farms: Sequence[FarmLocation]
    ) -> dict[uuid.UUID, LandCover]:
        """The dominant land-cover class under each farm (missing = unknown)."""
        ...


class NoLandCover:
    """No land-cover layer loaded (human gate): nothing is classified."""

    async def classify(
        self, session: AsyncSession, tenant_id: uuid.UUID, farms: Sequence[FarmLocation]
    ) -> dict[uuid.UUID, LandCover]:
        return {}


@dataclass
class InMemoryLandCover:
    by_farm: dict[uuid.UUID, LandCover] = field(default_factory=dict)

    async def classify(
        self, session: AsyncSession, tenant_id: uuid.UUID, farms: Sequence[FarmLocation]
    ) -> dict[uuid.UUID, LandCover]:
        return {f.farm_id: self.by_farm[f.farm_id] for f in farms if f.farm_id in self.by_farm}


# --------------------------------------------------------------------------- registry
@dataclass(frozen=True)
class Ports:
    segments: SegmentMembershipPort = field(default_factory=NoSegments)
    travel_claims: TravelClaimPort = field(default_factory=NoTravelClaims)
    land_cover: LandCoverPort = field(default_factory=NoLandCover)


_ports = Ports()


def get_ports() -> Ports:
    return _ports


def set_ports(
    *,
    segments: SegmentMembershipPort | None = None,
    travel_claims: TravelClaimPort | None = None,
    land_cover: LandCoverPort | None = None,
) -> Ports:
    """Register real adapters (startup of the owning package); returns the previous set."""
    global _ports
    previous = _ports
    changes = {
        k: v
        for k, v in (
            ("segments", segments),
            ("travel_claims", travel_claims),
            ("land_cover", land_cover),
        )
        if v is not None
    }
    _ports = replace(_ports, **changes)  # type: ignore[arg-type]
    return previous


@contextmanager
def override_ports(
    *,
    segments: SegmentMembershipPort | None = None,
    travel_claims: TravelClaimPort | None = None,
    land_cover: LandCoverPort | None = None,
) -> Iterator[Ports]:
    global _ports
    previous = set_ports(segments=segments, travel_claims=travel_claims, land_cover=land_cover)
    try:
        yield _ports
    finally:
        _ports = previous


__all__ = [
    "IMPLAUSIBLE_COVER",
    "FarmLocation",
    "InMemoryLandCover",
    "InMemorySegments",
    "InMemoryTravelClaims",
    "LandCover",
    "LandCoverPort",
    "NoLandCover",
    "NoSegments",
    "NoTravelClaims",
    "Ports",
    "SegmentMember",
    "SegmentMembershipPort",
    "TravelClaim",
    "TravelClaimPort",
    "get_ports",
    "override_ports",
    "set_ports",
]
