"""AN-004 farmer segments: preview a definition, save it, and the churn-risk list.

A *segment* is the WC-008 ``farmerapp.campaigns.segments.Segment`` — the same object a
campaign is sent to, so anything built here can be handed to a campaign without translation.
This module adds the analytics half of AN-004:

* ``preview`` — how many farmers a definition selects **inside the caller's role scope**
  (SPEC 2.6), how many of them carry current marketing consent (the reach a campaign would
  actually have) and the breakdown by crop, district, crop stage, acreage band, spend band,
  last-visit window, consent and app usage. Relative windows (``purchase_within_days`` and
  friends) are measured from the end of the AN-011 date range, not from wall-clock time, so
  a preview of a filtered range is reproducible.
* ``SavedSegment`` CRUD — a named definition the C32 builder stores and ``POST /v1/campaigns``
  can be created from (``saved_segment_id``). The campaign copies the definition, so editing
  a saved segment never rewrites what an earlier campaign was sent to.
* ``churn_list`` — farmers who bought before but have neither bought nor been visited within
  ``CHURN_WINDOW_DAYS`` (``farmers.churn_risk``), worst LTV first.

Every count is computed on the live tables (SPEC 5.3: P0 reads Postgres replicas; the
BigQuery marts ``mart_farmer_segments`` / ``mart_farmer_360`` hold the same definitions).
"""

from __future__ import annotations

import uuid
from collections import Counter
from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics import facts
from farmerapp.analytics.farmers import (
    CHURN_WINDOW_DAYS,
    churn_risk,
    directory_rows,
    mask_last4,
)
from farmerapp.analytics.filters import Scope
from farmerapp.analytics.owner_home import tenant_settings
from farmerapp.analytics.schemas import (
    ChurnListOut,
    ChurnRowOut,
    SavedSegmentListOut,
    SavedSegmentOut,
    SegmentFacetOut,
    SegmentPreviewOut,
)
from farmerapp.api.errors import ConflictError, NotFoundError
from farmerapp.auth.models import User
from farmerapp.campaigns.models import SavedSegment
from farmerapp.campaigns.segments import (
    Segment,
    SegmentContext,
    consented_farmer_ids,
    segment_query,
)
from farmerapp.khata.ledger import credit_settings

#: Acreage bands of AN-004 "farmers by ... acreage" (acres, lower bound inclusive).
ACREAGE_BANDS: tuple[tuple[str, float, float | None], ...] = (
    ("under_2", 0.0, 2.0),
    ("2_5", 2.0, 5.0),
    ("5_10", 5.0, 10.0),
    ("over_10", 10.0, None),
)
#: Lifetime spend bands (net sales, paise): none, < 5k, 5k-25k, 25k-1L, 1L+.
SPEND_BANDS: tuple[tuple[str, int, int | None], ...] = (
    ("none", 0, 1),
    ("under_5k", 1, 500_000),
    ("5k_25k", 500_000, 2_500_000),
    ("25k_1l", 2_500_000, 10_000_000),
    ("over_1l", 10_000_000, None),
)
#: Last-visit windows, matching the C30 directory filter.
VISIT_WINDOWS: tuple[tuple[str, int | None], ...] = (
    ("7d", 7),
    ("30d", 30),
    ("90d", 90),
    ("over_90d", None),
)
MAX_CHURN_ROWS = 200


class DuplicateSegmentError(ConflictError):
    code = "segment_name_taken"


def _band(value: float, bands: tuple[tuple[str, Any, Any], ...]) -> str:
    for key, low, high in bands:
        if value >= low and (high is None or value < high):
            return key
    return bands[-1][0]


def _visit_window(last_visit_at: datetime | None, as_of: datetime) -> str:
    if last_visit_at is None:
        return "never"
    days = (as_of - last_visit_at).days
    for key, limit in VISIT_WINDOWS:
        if limit is not None and days <= limit:
            return key
    return "over_90d"


def _facets(counter: Counter[str], order: list[str] | None = None) -> list[SegmentFacetOut]:
    keys = order if order is not None else sorted(counter, key=lambda k: (-counter[k], k))
    return [SegmentFacetOut(key=k, count=counter.get(k, 0)) for k in keys]


async def _rows(session: AsyncSession, scope: Scope, definition: Segment) -> list[Any]:
    """The scoped farmers the definition selects, with their directory figures."""
    due_days = credit_settings(await tenant_settings(session, scope.tenant_id)).credit_due_days
    rows = directory_rows(scope, due_days)
    _, end = scope.filters.bounds
    ctx = SegmentContext(tenant_id=scope.tenant_id, now=end)
    matching = segment_query(definition, ctx, consent=False)
    async with facts.hash_joins(session):
        result = await session.execute(select(rows).where(rows.c.id.in_(matching)))
        return list(result.all())


async def preview(session: AsyncSession, scope: Scope, definition: Segment) -> SegmentPreviewOut:
    """AN-004: counts and breakdowns of one segment definition inside the caller's scope."""
    rows = await _rows(session, scope, definition)
    consented_ids = set((await session.execute(consented_farmer_ids(scope.tenant_id))).scalars())
    _, end = scope.filters.bounds

    crops: Counter[str] = Counter()
    districts: Counter[str] = Counter()
    stages: Counter[str] = Counter()
    acreage: Counter[str] = Counter()
    spend_bands: Counter[str] = Counter()
    visits: Counter[str] = Counter()
    consent: Counter[str] = Counter()
    app: Counter[str] = Counter()
    ltv_total = spend_total = churn = consented = app_users = 0

    for r in rows:
        for code in set(r.crops or []):
            crops[code] += 1
        districts[r.district] += 1
        for stage in set(r.stages or []):
            stages[stage] += 1
        acreage[_band(float(r.acres or 0), ACREAGE_BANDS)] += 1
        spend = facts._paise(r.spend)
        spend_bands[_band(spend, SPEND_BANDS)] += 1
        visits[_visit_window(r.last_visit_at, end)] += 1
        has_consent = r.id in consented_ids
        consent["granted" if has_consent else "withheld"] += 1
        consented += has_consent
        app["app_user" if r.app_user else "no_app"] += 1
        app_users += bool(r.app_user)
        ltv_total += facts._paise(r.ltv)
        spend_total += spend
        churn += churn_risk(
            last_purchase_at=r.last_purchase_at,
            last_visit_at=r.last_visit_at,
            orders=int(r.orders or 0),
            as_of=end,
        )

    matched = len(rows)
    return SegmentPreviewOut(
        filters=scope.echo(),
        definition=definition,
        matched=matched,
        consented=consented,
        excluded_no_consent=matched - consented,
        app_users=app_users,
        churn_risk=churn,
        churn_window_days=CHURN_WINDOW_DAYS,
        ltv_paise=ltv_total,
        spend_paise=spend_total,
        by_crop=_facets(crops),
        by_district=_facets(districts),
        by_stage=_facets(stages),
        by_acreage_band=_facets(acreage, [k for k, _, _ in ACREAGE_BANDS]),
        by_spend_band=_facets(spend_bands, [k for k, _, _ in SPEND_BANDS]),
        by_last_visit=_facets(visits, [k for k, _ in VISIT_WINDOWS] + ["never"]),
        by_consent=_facets(consent, ["granted", "withheld"]),
        by_app_usage=_facets(app, ["app_user", "no_app"]),
    )


async def churn_list(session: AsyncSession, scope: Scope, *, days: int, limit: int) -> ChurnListOut:
    """AN-004 churn-risk list: prior customers gone quiet, biggest LTV first."""
    due_days = credit_settings(await tenant_settings(session, scope.tenant_id)).credit_due_days
    rows = directory_rows(scope, due_days)
    _, end = scope.filters.bounds
    async with facts.hash_joins(session):
        fetched = list((await session.execute(select(rows))).all())
    at_risk = [
        r
        for r in fetched
        if churn_risk(
            last_purchase_at=r.last_purchase_at,
            last_visit_at=r.last_visit_at,
            orders=int(r.orders or 0),
            as_of=end,
            days=days,
        )
    ]
    at_risk.sort(key=lambda r: (-facts._paise(r.ltv), r.name))
    items = [
        ChurnRowOut(
            id=r.id,
            name=r.name,
            phone_masked=mask_last4(r.phone_last4),
            village=r.village,
            district=r.district,
            store_id=r.store_id,
            registered_by=r.registered_by,
            crops=sorted(r.crops or []),
            ltv_paise=facts._paise(r.ltv),
            spend_paise=facts._paise(r.spend),
            orders=int(r.orders or 0),
            last_purchase_at=r.last_purchase_at,
            last_visit_at=r.last_visit_at,
            days_since_last_purchase=(
                None if r.last_purchase_at is None else max((end - r.last_purchase_at).days, 0)
            ),
            days_since_last_visit=(
                None if r.last_visit_at is None else max((end - r.last_visit_at).days, 0)
            ),
            balance_paise=int(r.balance or 0),
            overdue_paise=int(r.overdue or 0),
            credit_risk=r.risk,
            app_user=bool(r.app_user),
            consent_marketing=bool(r.consent_marketing),
        )
        for r in at_risk[:limit]
    ]
    return ChurnListOut(
        filters=scope.echo(),
        window_days=days,
        total=len(at_risk),
        items=items,
    )


# --------------------------------------------------------------------------- saved segments
def to_out(row: SavedSegment) -> SavedSegmentOut:
    return SavedSegmentOut(
        id=row.id,
        name=row.name,
        description=row.description,
        definition=Segment.model_validate(row.definition or {}),
        created_by=row.created_by,
        created_at=row.created_at,
        updated_at=row.updated_at,
        last_count=row.last_count,
        last_counted_at=row.last_counted_at,
        version=row.version,
    )


async def list_saved(session: AsyncSession, tenant_id: uuid.UUID) -> SavedSegmentListOut:
    rows = await session.scalars(
        select(SavedSegment)
        .where(SavedSegment.tenant_id == tenant_id, SavedSegment.deleted_at.is_(None))
        .order_by(SavedSegment.name, SavedSegment.id)
        .limit(200)
    )
    return SavedSegmentListOut(items=[to_out(r) for r in rows])


async def get_saved(
    session: AsyncSession, tenant_id: uuid.UUID, segment_id: uuid.UUID
) -> SavedSegment:
    row = await session.get(SavedSegment, segment_id)
    if row is None or row.tenant_id != tenant_id or row.deleted_at is not None:
        raise NotFoundError("Segment not found.")
    return row


async def _assert_free(
    session: AsyncSession, tenant_id: uuid.UUID, name: str, *, exclude: uuid.UUID | None = None
) -> None:
    stmt = (
        select(func.count())
        .select_from(SavedSegment)
        .where(
            SavedSegment.tenant_id == tenant_id,
            SavedSegment.deleted_at.is_(None),
            func.lower(SavedSegment.name) == name.lower(),
        )
    )
    if exclude is not None:
        stmt = stmt.where(SavedSegment.id != exclude)
    if await session.scalar(stmt):
        raise DuplicateSegmentError("A segment with that name already exists.")


async def create_saved(
    session: AsyncSession,
    actor: User,
    *,
    name: str,
    description: str | None,
    definition: Segment,
    count: int | None = None,
    now: datetime | None = None,
) -> SavedSegment:
    await _assert_free(session, actor.tenant_id, name)
    row = SavedSegment(
        tenant_id=actor.tenant_id,
        name=name,
        description=description,
        definition=definition.model_dump(mode="json", exclude_defaults=True),
        created_by=actor.id,
        last_count=count,
        last_counted_at=now if count is not None else None,
    )
    session.add(row)
    await session.flush()
    return row


async def update_saved(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    row: SavedSegment,
    changes: dict[str, Any],
    *,
    count: int | None = None,
    now: datetime | None = None,
) -> SavedSegment:
    if "name" in changes:
        await _assert_free(session, tenant_id, changes["name"], exclude=row.id)
        row.name = changes["name"]
    if "description" in changes:
        row.description = changes["description"]
    if "definition" in changes:
        # An explicit `null` clears the criteria rather than failing validation.
        definition = Segment.model_validate(changes["definition"] or {})
        row.definition = definition.model_dump(mode="json", exclude_defaults=True)
        row.last_count, row.last_counted_at = count, (now if count is not None else None)
    await session.flush()
    await session.refresh(row)  # the `updated_at` / `version` trigger fired server-side
    return row


async def delete_saved(session: AsyncSession, row: SavedSegment, now: datetime) -> None:
    row.deleted_at = now
    await session.flush()


__all__ = [
    "ACREAGE_BANDS",
    "MAX_CHURN_ROWS",
    "SPEND_BANDS",
    "VISIT_WINDOWS",
    "DuplicateSegmentError",
    "churn_list",
    "create_saved",
    "delete_saved",
    "get_saved",
    "list_saved",
    "preview",
    "to_out",
    "update_saved",
]
