"""AN-011 dashboard filters and their role scope (SPEC 2.6).

Every analytics endpoint takes the same query parameters:

``from`` / ``to``
    IST calendar dates, both inclusive. Default: the 30 days ending today (IST). ``from``
    after ``to`` or a range longer than ``MAX_RANGE_DAYS`` is ``422 invalid_date_range``.
``cluster_id`` / ``store_id`` / ``officer_id`` / ``crop_id``
    Optional narrowing. An id the caller cannot see (another tenant, another cluster for a
    cluster head, a colleague for an officer) is ``404 not_found``; a combination that
    cannot match (a store outside the cluster, an officer outside the store / cluster) is
    ``422 invalid_filter_combination``.

The tenant always comes from the token. Every response echoes the applied filters under
``filters`` (``FiltersOut``) so the console can keep them in the URL (AN-011 "filters
persist in URL").

``resolve_scope`` turns (actor, filters) into a ``Scope``: which stores, which officers and
which farmers the figures are computed over.

=================================== =========================================================
role                                scope
=================================== =========================================================
owner / director / tenant admin /   whole tenant
auditor / accountant
cluster head                        stores of their cluster; officers placed in it
store manager                       their store; its officers
field officer                       their own figures only (own visits, own orders, farmers
                                    they registered); ``officer_id`` may only name themself
=================================== =========================================================
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Annotated, Any
from zoneinfo import ZoneInfo

from fastapi import Depends, Query
from geoalchemy2 import Geometry
from pydantic import BaseModel, Field
from sqlalchemy import (
    ColumnElement,
    Date,
    Select,
    SQLColumnExpression,
    cast,
    false,
    func,
    literal_column,
    select,
)
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.db.geo import SRID
from farmerapp.farmers.models import CropPlot, Farm, Farmer
from farmerapp.tenants.models import Cluster, Store, Village

IST = ZoneInfo("Asia/Kolkata")
POINT_GEOM = Geometry(geometry_type="POINT", srid=SRID)
IST_NAME = "Asia/Kolkata"
#: Rendered inline (not a bind parameter) so a GROUP BY on an IST date matches its SELECT.
IST_SQL: ColumnElement[str] = literal_column(f"'{IST_NAME}'")
DEFAULT_RANGE_DAYS = 30
MAX_RANGE_DAYS = 366

#: Roles that see the whole tenant (SPEC 2.6 "Read" plus tenant admin / accountant).
TENANT_WIDE = frozenset(
    {
        UserRole.OWNER,
        UserRole.DIRECTOR,
        UserRole.TENANT_ADMIN,
        UserRole.AUDITOR,
        UserRole.ACCOUNTANT,
    }
)
#: SPEC 2.6 "Officer location track": never store managers or other officers.
LOCATION_ROLES = frozenset(
    {
        UserRole.OWNER,
        UserRole.DIRECTOR,
        UserRole.TENANT_ADMIN,
        UserRole.AUDITOR,
        UserRole.CLUSTER_HEAD,
        UserRole.FIELD_OFFICER,
    }
)


class InvalidDateRangeError(AppError):
    status = 422
    code = "invalid_date_range"


class InvalidFilterCombinationError(AppError):
    status = 422
    code = "invalid_filter_combination"


# --------------------------------------------------------------------------- time helpers
def today_ist(now: datetime | None = None) -> date:
    return (now or datetime.now(UTC)).astimezone(IST).date()


def ist_start(day: date) -> datetime:
    """The UTC instant at which the IST calendar ``day`` starts."""
    return datetime.combine(day, time.min, tzinfo=IST).astimezone(UTC)


def ist_bounds(first: date, last: date) -> tuple[datetime, datetime]:
    """``[start, end)`` in UTC covering the IST days ``first`` .. ``last`` inclusive."""
    return ist_start(first), ist_start(last + timedelta(days=1))


def ist_date(column: SQLColumnExpression[Any]) -> ColumnElement[date]:
    """SQL: the IST calendar date of a ``timestamptz`` column."""
    return cast(func.timezone(IST_SQL, column), Date)


def to_ist_date(ts: datetime) -> date:
    return ts.astimezone(IST).date()


def year_before(day: date) -> date:
    """Same calendar day a year earlier (29 February -> 28 February)."""
    try:
        return day.replace(year=day.year - 1)
    except ValueError:
        return day.replace(year=day.year - 1, day=28)


# --------------------------------------------------------------------------- filters
@dataclass(frozen=True)
class AnalyticsFilters:
    """The AN-011 filter set as received (validated, not yet scoped)."""

    from_: date
    to: date
    cluster_id: uuid.UUID | None = None
    store_id: uuid.UUID | None = None
    officer_id: uuid.UUID | None = None
    crop_id: uuid.UUID | None = None

    @property
    def days(self) -> int:
        return (self.to - self.from_).days + 1

    @property
    def bounds(self) -> tuple[datetime, datetime]:
        return ist_bounds(self.from_, self.to)

    def last_year(self) -> AnalyticsFilters:
        return AnalyticsFilters(
            from_=year_before(self.from_),
            to=year_before(self.to),
            cluster_id=self.cluster_id,
            store_id=self.store_id,
            officer_id=self.officer_id,
            crop_id=self.crop_id,
        )


def analytics_filters(
    from_: Annotated[
        date | None,
        Query(alias="from", description="First IST day (inclusive). Default: `to` - 29 days."),
    ] = None,
    to: Annotated[
        date | None, Query(description="Last IST day (inclusive). Default: today (IST).")
    ] = None,
    cluster_id: Annotated[uuid.UUID | None, Query(description="Cluster to narrow to.")] = None,
    store_id: Annotated[uuid.UUID | None, Query(description="Store to narrow to.")] = None,
    officer_id: Annotated[
        uuid.UUID | None, Query(description="Field officer to narrow to.")
    ] = None,
    crop_id: Annotated[
        uuid.UUID | None, Query(description="Crop: farmers with a plot of it.")
    ] = None,
) -> AnalyticsFilters:
    last = to or today_ist()
    first = from_ or last - timedelta(days=DEFAULT_RANGE_DAYS - 1)
    if first > last:
        raise InvalidDateRangeError("`from` must be on or before `to`.")
    if (last - first).days + 1 > MAX_RANGE_DAYS:
        raise InvalidDateRangeError(f"The date range may span at most {MAX_RANGE_DAYS} days.")
    return AnalyticsFilters(
        from_=first,
        to=last,
        cluster_id=cluster_id,
        store_id=store_id,
        officer_id=officer_id,
        crop_id=crop_id,
    )


Filters = Annotated[AnalyticsFilters, Depends(analytics_filters)]


class FiltersOut(BaseModel):
    """The applied filters, echoed in every analytics response (AN-011)."""

    from_: date = Field(alias="from", serialization_alias="from")
    to: date
    cluster_id: uuid.UUID | None = None
    store_id: uuid.UUID | None = None
    officer_id: uuid.UUID | None = None
    crop_id: uuid.UUID | None = None
    days: int = Field(description="Days in the range (inclusive).")
    scope: str = Field(
        description="Role narrowing applied on top: `tenant`, `cluster`, `store` or `own`."
    )

    model_config = {"populate_by_name": True}


# --------------------------------------------------------------------------- scope
@dataclass(frozen=True)
class StoreInfo:
    id: uuid.UUID
    code: str
    name: str
    cluster_id: uuid.UUID | None
    district: str
    lat: float | None
    lon: float | None


@dataclass(frozen=True)
class OfficerInfo:
    id: uuid.UUID
    name: str
    phone: str
    store_id: uuid.UUID | None
    cluster_id: uuid.UUID | None
    status: str


@dataclass(frozen=True)
class Scope:
    """What the figures of one request are computed over.

    ``store_ids`` / ``officer_ids`` are ``None`` when there is no narrowing (whole tenant).
    ``own_officer_id`` is set for the field officer's own view and for an ``officer_id``
    filter: sales are the orders they placed and farmers the ones they registered.
    """

    actor: User
    filters: AnalyticsFilters
    level: str  # tenant | cluster | store | own
    stores: tuple[StoreInfo, ...]
    officers: tuple[OfficerInfo, ...]
    store_ids: frozenset[uuid.UUID] | None
    officer_ids: frozenset[uuid.UUID] | None
    own_officer_id: uuid.UUID | None
    crop_id: uuid.UUID | None

    @property
    def tenant_id(self) -> uuid.UUID:
        return self.actor.tenant_id

    @property
    def show_location(self) -> bool:
        """SPEC 2.6: location-derived figures only for track-visible roles."""
        return UserRole(self.actor.role) in LOCATION_ROLES

    def echo(self, filters: AnalyticsFilters | None = None) -> FiltersOut:
        f = filters or self.filters
        return FiltersOut(
            from_=f.from_,
            to=f.to,
            cluster_id=f.cluster_id,
            store_id=f.store_id,
            officer_id=f.officer_id,
            crop_id=f.crop_id,
            days=f.days,
            scope=self.level,
        )

    def with_filters(self, filters: AnalyticsFilters) -> Scope:
        """Same narrowing over another date range (same period last year)."""
        return Scope(
            actor=self.actor,
            filters=filters,
            level=self.level,
            stores=self.stores,
            officers=self.officers,
            store_ids=self.store_ids,
            officer_ids=self.officer_ids,
            own_officer_id=self.own_officer_id,
            crop_id=self.crop_id,
        )

    # --- SQL filters -------------------------------------------------------------------
    def crop_farmers(self) -> Select[tuple[uuid.UUID]]:
        return (
            select(Farm.farmer_id)
            .join(CropPlot, CropPlot.farm_id == Farm.id)
            .where(
                Farm.tenant_id == self.tenant_id,
                Farm.deleted_at.is_(None),
                CropPlot.deleted_at.is_(None),
                CropPlot.crop_id == self.crop_id,
            )
        )

    def farmer_filters(self) -> list[ColumnElement[bool]]:
        """Filters on ``farmer`` rows (store via village, officer via registration, crop)."""
        out: list[ColumnElement[bool]] = [
            Farmer.tenant_id == self.tenant_id,
            Farmer.deleted_at.is_(None),
        ]
        if self.store_ids is not None:
            villages = select(Village.id).where(
                Village.tenant_id == self.tenant_id, Village.store_id.in_(self.store_ids)
            )
            out.append(Farmer.village_id.in_(villages) if self.store_ids else false())
        if self.own_officer_id is not None:
            out.append(Farmer.registered_by == self.own_officer_id)
        if self.crop_id is not None:
            out.append(Farmer.id.in_(self.crop_farmers()))
        return out

    def farmer_ids(self) -> Select[tuple[uuid.UUID]]:
        return select(Farmer.id).where(*self.farmer_filters())

    def farmer_column_filters(self, column: SQLColumnExpression[Any]) -> list[ColumnElement[bool]]:
        """Narrow a ``farmer_id`` column to the scoped farmers (only when narrowed)."""
        if self.store_ids is None and self.own_officer_id is None and self.crop_id is None:
            return []
        return [column.in_(self.farmer_ids())]

    def store_column_filters(self, column: SQLColumnExpression[Any]) -> list[ColumnElement[bool]]:
        if self.store_ids is None:
            return []
        return [column.in_(self.store_ids) if self.store_ids else false()]

    def officer_column_filters(self, column: SQLColumnExpression[Any]) -> list[ColumnElement[bool]]:
        if self.officer_ids is None:
            return []
        return [column.in_(self.officer_ids) if self.officer_ids else false()]

    def crop_column_filters(self, column: SQLColumnExpression[Any]) -> list[ColumnElement[bool]]:
        if self.crop_id is None:
            return []
        return [column.in_(self.crop_farmers())]


async def _stores(session: AsyncSession, tenant_id: uuid.UUID) -> list[StoreInfo]:
    geom = cast(Store.location, POINT_GEOM)
    rows = await session.execute(
        select(
            Store.id,
            Store.code,
            Store.name,
            Store.cluster_id,
            Store.district,
            func.ST_Y(geom),
            func.ST_X(geom),
        )
        .where(Store.tenant_id == tenant_id, Store.deleted_at.is_(None))
        .order_by(Store.code)
    )
    return [
        StoreInfo(
            id=r[0],
            code=r[1],
            name=r[2],
            cluster_id=r[3],
            district=r[4],
            lat=float(r[5]) if r[5] is not None else None,
            lon=float(r[6]) if r[6] is not None else None,
        )
        for r in rows
    ]


async def _officers(session: AsyncSession, tenant_id: uuid.UUID) -> list[OfficerInfo]:
    rows = await session.execute(
        select(User.id, User.name, User.phone, User.store_id, User.cluster_id, User.status)
        .where(
            User.tenant_id == tenant_id,
            User.role == UserRole.FIELD_OFFICER.value,
            User.deleted_at.is_(None),
        )
        .order_by(User.name, User.id)
    )
    return [OfficerInfo(*r) for r in rows]


async def resolve_scope(session: AsyncSession, actor: User, filters: AnalyticsFilters) -> Scope:
    """Narrow ``filters`` by the actor's role; validate ids and combinations."""
    role = UserRole(actor.role)
    tid = actor.tenant_id
    all_stores = await _stores(session, tid)
    all_officers = await _officers(session, tid)

    # 1. Role narrowing.
    level = "tenant"
    stores = all_stores
    officers = all_officers
    own: uuid.UUID | None = None
    narrowed = False
    if role == UserRole.CLUSTER_HEAD:
        level, narrowed = "cluster", True
        stores = [s for s in all_stores if actor.cluster_id and s.cluster_id == actor.cluster_id]
        ids = {s.id for s in stores}
        officers = [
            o
            for o in all_officers
            if (o.store_id in ids) or (o.store_id is None and o.cluster_id == actor.cluster_id)
        ]
        if actor.cluster_id is None:
            officers = []
    elif role == UserRole.STORE_MANAGER:
        level, narrowed = "store", True
        stores = [s for s in all_stores if actor.store_id and s.id == actor.store_id]
        officers = [o for o in all_officers if actor.store_id and o.store_id == actor.store_id]
    elif role == UserRole.FIELD_OFFICER:
        level, narrowed, own = "own", True, actor.id
        officers = [o for o in all_officers if o.id == actor.id]
    elif role not in TENANT_WIDE:
        level, narrowed = "none", True
        stores, officers = [], []

    # 2. Filters: ids must be visible, combinations consistent.
    if filters.cluster_id is not None:
        clusters = {s.cluster_id for s in stores}
        if role in TENANT_WIDE or role == UserRole.FIELD_OFFICER:
            exists = await session.scalar(
                select(Cluster.id).where(
                    Cluster.id == filters.cluster_id,
                    Cluster.tenant_id == tid,
                    Cluster.deleted_at.is_(None),
                )
            )
            if exists is None:
                raise NotFoundError("Cluster not found.")
        elif filters.cluster_id not in clusters and filters.cluster_id != actor.cluster_id:
            raise NotFoundError("Cluster not found.")
        stores = [s for s in stores if s.cluster_id == filters.cluster_id]
        ids = {s.id for s in stores}
        officers = [
            o
            for o in officers
            if o.store_id in ids or (o.store_id is None and o.cluster_id == filters.cluster_id)
        ]
        narrowed = True
    if filters.store_id is not None:
        store = next((s for s in all_stores if s.id == filters.store_id), None)
        if store is None:
            raise NotFoundError("Store not found.")
        if filters.cluster_id is not None and store.cluster_id != filters.cluster_id:
            raise InvalidFilterCombinationError("The store is not in the selected cluster.")
        if store not in stores:
            raise NotFoundError("Store not found.")
        stores = [store]
        officers = [o for o in officers if o.store_id == store.id]
        narrowed = True
    if filters.officer_id is not None:
        officer = next((o for o in all_officers if o.id == filters.officer_id), None)
        if officer is None or (role == UserRole.FIELD_OFFICER and officer.id != actor.id):
            raise NotFoundError("Officer not found.")
        if officer not in officers:
            if filters.store_id is not None or filters.cluster_id is not None:
                in_role_scope = role in TENANT_WIDE or _officer_in_role_scope(actor, officer)
                if in_role_scope:
                    raise InvalidFilterCombinationError(
                        "The officer is not in the selected store / cluster."
                    )
            raise NotFoundError("Officer not found.")
        officers = [officer]
        own = officer.id
        narrowed = True
    if filters.crop_id is not None:
        crop = await session.scalar(
            select(Crop.id).where(Crop.id == filters.crop_id, Crop.tenant_id == tid)
        )
        if crop is None:
            raise NotFoundError("Crop not found.")

    store_narrowed = (role not in TENANT_WIDE and role != UserRole.FIELD_OFFICER) or (
        filters.cluster_id is not None or filters.store_id is not None
    )
    return Scope(
        actor=actor,
        filters=filters,
        level=level,
        stores=tuple(stores),
        officers=tuple(officers),
        store_ids=frozenset(s.id for s in stores) if store_narrowed else None,
        officer_ids=frozenset(o.id for o in officers) if narrowed else None,
        own_officer_id=own,
        crop_id=filters.crop_id,
    )


def _officer_in_role_scope(actor: User, officer: OfficerInfo) -> bool:
    role = UserRole(actor.role)
    if role == UserRole.CLUSTER_HEAD:
        return actor.cluster_id is not None and officer.cluster_id == actor.cluster_id
    if role == UserRole.STORE_MANAGER:
        return actor.store_id is not None and officer.store_id == actor.store_id
    return False


__all__ = [
    "IST",
    "IST_NAME",
    "IST_SQL",
    "LOCATION_ROLES",
    "MAX_RANGE_DAYS",
    "POINT_GEOM",
    "TENANT_WIDE",
    "AnalyticsFilters",
    "Filters",
    "FiltersOut",
    "InvalidDateRangeError",
    "InvalidFilterCombinationError",
    "OfficerInfo",
    "Scope",
    "StoreInfo",
    "analytics_filters",
    "ist_bounds",
    "ist_date",
    "ist_start",
    "resolve_scope",
    "to_ist_date",
    "today_ist",
    "year_before",
]
