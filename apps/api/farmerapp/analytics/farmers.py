"""WC-003 farmers directory (C30) and farmer 360 (C31).

Both read the live tables, so a profile reflects the latest sync the moment it is merged
(WC-003 "profile reflects latest sync"; SPEC 5.3: P0 reads Postgres, not the marts).

Directory: search ``q`` (name contains; a 4-digit ``q`` also matches the phone's last four;
village name contains), filters ``district``, ``stage`` (a live crop plot at that stage),
``credit_risk`` (``low`` / ``medium`` / ``high``, see ``kpi.credit_risk``), ``last_visit``
(``7d`` / ``30d`` / ``90d`` = a visit in the last N days up to ``to``; ``over_90d``; ``never``)
plus the AN-011 set (store / cluster via the village's store, officer = registered by, crop =
has a plot of it). Sorts: ``name``, ``last_visit``, ``last_purchase``, ``ltv``, ``balance``,
``overdue`` (``-`` prefix = descending; nulls last). Cursor: opaque offset.

The directory shows ``phone_masked`` only (AN-014 PII minimisation); the 360 is the console
detail and carries the full phone.

Credit figures are as of the end of ``to``, per farmer x store ledger (a store's credits
settle that store's debits, oldest due first), summed per farmer.
"""

from __future__ import annotations

import base64
import binascii
import json
import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta
from typing import Any, Literal

from sqlalchemy import (
    Date,
    String,
    and_,
    case,
    cast,
    func,
    or_,
    select,
)
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics import facts
from farmerapp.analytics.filters import Scope, ist_start, to_ist_date
from farmerapp.analytics.kpi import (
    ACTIVE_WINDOW_DAYS,
    active_farmers,
    credit_book,
    credit_risk,
)
from farmerapp.analytics.owner_home import tenant_settings
from farmerapp.analytics.schemas import (
    AppUsageOut,
    ConsentEventOut,
    ConsentOut,
    Farmer360Out,
    FarmerCropPlotOut,
    FarmerDirectoryOut,
    FarmerFarmOut,
    FarmerOrderOut,
    FarmerProfileOut,
    FarmerRow,
    FarmerVisitOut,
    KhataSummaryOut,
)
from farmerapp.api.errors import AppError, NotFoundError
from farmerapp.api.pagination import InvalidCursorError
from farmerapp.auth.models import RefreshToken, User
from farmerapp.catalog.crops import Crop
from farmerapp.farmers.models import ConsentRecord, ConsentSubject, CropPlot, Farm, Farmer
from farmerapp.khata.ledger import credit_settings
from farmerapp.khata.models import CreditLimit, EntryType, KhataEntry
from farmerapp.orders.models import Order, OrderLine
from farmerapp.payments.models import Payment, PaymentMode
from farmerapp.tenants.models import Village
from farmerapp.visits.models import Visit

SORTS = ("name", "last_visit", "last_purchase", "ltv", "balance", "overdue")
LastVisit = Literal["7d", "30d", "90d", "over_90d", "never"]
Risk = Literal["low", "medium", "high"]
HISTORY_LIMIT = 50
APP_USAGE_PROXY = "refresh_token_issuance"


class InvalidSortError(AppError):
    status = 422
    code = "invalid_sort"


def encode_offset(offset: int) -> str:
    return base64.urlsafe_b64encode(json.dumps({"o": offset}).encode()).decode().rstrip("=")


def decode_offset(token: str | None) -> int:
    if not token:
        return 0
    try:
        padded = token + "=" * (-len(token) % 4)
        value = int(json.loads(base64.urlsafe_b64decode(padded.encode()).decode())["o"])
    except (ValueError, KeyError, TypeError, binascii.Error, UnicodeDecodeError) as exc:
        raise InvalidCursorError("Malformed cursor.") from exc
    if value < 0:
        raise InvalidCursorError("Malformed cursor.")
    return value


def mask_phone(phone: str) -> str:
    return "*" * max(len(phone) - 4, 0) + phone[-4:]


def _due_date(due_days: int) -> Any:
    """SQL twin of ``khata.aging.effective_due_date``."""
    harvest_end = cast(
        KhataEntry.harvest_month + func.make_interval(0, 1) - func.make_interval(0, 0, 0, 1),
        Date,
    )
    created = cast(func.timezone("UTC", KhataEntry.created_at), Date) + due_days
    return func.coalesce(KhataEntry.due_date, harvest_end, created)


def credit_by_farmer(as_of: date, until: datetime, due_days: int, tenant_id: uuid.UUID) -> Any:
    """Subquery ``farmer_id, balance, overdue, overdue_61``: per farmer x store ledger, then
    summed per farmer (FIFO ageing in closed form: credits cover the oldest due first, so the
    uncovered part of debits due before D is ``max(sum(debits due < D) - credits, 0)``)."""
    due = _due_date(due_days)
    debit = KhataEntry.type == EntryType.DEBIT.value
    credit_sum = func.sum(case((~debit, KhataEntry.amount_paise), else_=0))
    debit_sum = func.sum(case((debit, KhataEntry.amount_paise), else_=0))
    due_before = func.sum(case((and_(debit, due < as_of), KhataEntry.amount_paise), else_=0))
    due_before_61 = func.sum(
        case((and_(debit, due < as_of - timedelta(days=60)), KhataEntry.amount_paise), else_=0)
    )
    accounts = (
        select(
            KhataEntry.farmer_id.label("farmer_id"),
            (debit_sum - credit_sum).label("balance"),
            func.greatest(due_before - credit_sum, 0).label("overdue"),
            func.greatest(due_before_61 - credit_sum, 0).label("overdue_61"),
        )
        .where(KhataEntry.tenant_id == tenant_id, KhataEntry.created_at < until)
        .group_by(KhataEntry.farmer_id, KhataEntry.store_id)
        .subquery("accounts")
    )
    return (
        select(
            accounts.c.farmer_id,
            func.sum(func.greatest(accounts.c.balance, 0)).label("balance"),
            func.sum(accounts.c.overdue).label("overdue"),
            func.sum(accounts.c.overdue_61).label("overdue_61"),
        )
        .group_by(accounts.c.farmer_id)
        .subquery("credit")
    )


def _directory_rows(scope: Scope, due_days: int) -> Any:
    f = scope.filters
    _, end = f.bounds
    tid = scope.tenant_id
    last_visit = (
        select(Visit.farmer_id, func.max(Visit.checkin_at).label("at"))
        .where(Visit.tenant_id == tid, Visit.deleted_at.is_(None), Visit.checkin_at < end)
        .group_by(Visit.farmer_id)
        .subquery("last_visit")
    )
    at = facts.sold_at()
    last_purchase = (
        select(Order.farmer_id, func.max(at).label("at"))
        .where(
            Order.tenant_id == tid,
            Order.deleted_at.is_(None),
            Order.status.in_(facts.FULFILLED),
            Order.farmer_id.is_not(None),
            at < end,
        )
        .group_by(Order.farmer_id)
        .subquery("last_purchase")
    )
    lines = facts.tenant_sales_lines(tid)
    ltv = (
        select(lines.c.farmer_id, func.sum(lines.c.net - lines.c.cost).label("ltv"))
        .where(lines.c.farmer_id.is_not(None), lines.c.sold_at < end)
        .group_by(lines.c.farmer_id)
        .subquery("ltv")
    )
    credit = credit_by_farmer(f.to, end, due_days, tid)
    plots = (
        select(
            Farm.farmer_id,
            func.array_agg(func.distinct(Crop.code)).label("crops"),
            func.array_remove(func.array_agg(func.distinct(CropPlot.stage)), None).label("stages"),
        )
        .join(CropPlot, and_(CropPlot.farm_id == Farm.id, CropPlot.deleted_at.is_(None)))
        .join(Crop, Crop.id == CropPlot.crop_id)
        .where(Farm.tenant_id == tid, Farm.deleted_at.is_(None))
        .group_by(Farm.farmer_id)
        .subquery("plots")
    )
    acres = (
        select(Farm.farmer_id, func.sum(Farm.area_acres).label("acres"))
        .where(Farm.tenant_id == tid, Farm.deleted_at.is_(None))
        .group_by(Farm.farmer_id)
        .subquery("acres")
    )
    overdue = func.coalesce(credit.c.overdue, 0)
    risk = case(
        (func.coalesce(credit.c.overdue_61, 0) > 0, "high"),
        (overdue > 0, "medium"),
        else_="low",
    )
    return (
        select(
            Farmer.id.label("id"),
            Farmer.name.label("name"),
            Farmer.phone.label("phone"),
            Farmer.village_id.label("village_id"),
            Village.name.label("village"),
            Village.district.label("district"),
            Village.store_id.label("store_id"),
            Farmer.registered_by.label("registered_by"),
            func.coalesce(plots.c.crops, cast([], ARRAY(String))).label("crops"),
            func.coalesce(plots.c.stages, cast([], ARRAY(String))).label("stages"),
            func.coalesce(acres.c.acres, 0).label("acres"),
            last_visit.c.at.label("last_visit_at"),
            last_purchase.c.at.label("last_purchase_at"),
            func.coalesce(credit.c.balance, 0).label("balance"),
            overdue.label("overdue"),
            risk.label("risk"),
            func.coalesce(ltv.c.ltv, 0).label("ltv"),
            (Farmer.user_id.is_not(None)).label("app_user"),
            Farmer.consent_marketing.label("consent_marketing"),
            Farmer.phone_last4.label("phone_last4"),
            Farmer.created_at.label("created_at"),
        )
        .join(Village, Village.id == Farmer.village_id)
        .outerjoin(last_visit, last_visit.c.farmer_id == Farmer.id)
        .outerjoin(last_purchase, last_purchase.c.farmer_id == Farmer.id)
        .outerjoin(ltv, ltv.c.farmer_id == Farmer.id)
        .outerjoin(credit, credit.c.farmer_id == Farmer.id)
        .outerjoin(plots, plots.c.farmer_id == Farmer.id)
        .outerjoin(acres, acres.c.farmer_id == Farmer.id)
        .where(*scope.farmer_filters())
        .subquery("directory")
    )


async def directory(
    session: AsyncSession,
    scope: Scope,
    *,
    q: str | None,
    district: str | None,
    stage: str | None,
    risk: Risk | None,
    last_visit: LastVisit | None,
    sort: str,
    cursor: str | None,
    limit: int,
) -> FarmerDirectoryOut:
    settings = await tenant_settings(session, scope.tenant_id)
    due_days = credit_settings(settings).credit_due_days
    rows = _directory_rows(scope, due_days)
    where: list[Any] = []
    if q:
        term = q.strip()
        like = f"%{term}%"
        conds = [rows.c.name.ilike(like), rows.c.village.ilike(like)]
        if term.isdigit() and len(term) == 4:
            conds.append(rows.c.phone_last4 == term)
        where.append(or_(*conds))
    if district:
        where.append(func.lower(rows.c.district) == district.lower())
    if stage:
        where.append(rows.c.stages.any(stage))
    if risk:
        where.append(rows.c.risk == risk)
    if last_visit:
        _, end = scope.filters.bounds
        if last_visit == "never":
            where.append(rows.c.last_visit_at.is_(None))
        elif last_visit == "over_90d":
            where.append(
                or_(rows.c.last_visit_at.is_(None), rows.c.last_visit_at < end - timedelta(days=90))
            )
        else:
            n = int(last_visit[:-1])
            where.append(rows.c.last_visit_at >= end - timedelta(days=n))

    desc = sort.startswith("-")
    key = sort.lstrip("-")
    if key not in SORTS:
        raise InvalidSortError(f"`sort` must be one of {', '.join(SORTS)} (prefix - for desc).")
    column = {
        "name": rows.c.name,
        "last_visit": rows.c.last_visit_at,
        "last_purchase": rows.c.last_purchase_at,
        "ltv": rows.c.ltv,
        "balance": rows.c.balance,
        "overdue": rows.c.overdue,
    }[key]
    ordering = (column.desc() if desc else column.asc()).nulls_last()
    offset = decode_offset(cursor)
    async with facts.hash_joins(session):
        total = await session.scalar(select(func.count()).select_from(rows).where(*where))
        result = await session.execute(
            select(rows)
            .where(*where)
            .order_by(ordering, rows.c.name, rows.c.id)
            .offset(offset)
            .limit(limit + 1)
        )
        fetched = result.all()
    items = [
        FarmerRow(
            id=r.id,
            name=r.name,
            phone_masked=mask_phone(r.phone),
            village_id=r.village_id,
            village=r.village,
            district=r.district,
            store_id=r.store_id,
            registered_by=r.registered_by,
            crops=sorted(r.crops or []),
            stages=sorted(r.stages or []),
            acres=float(r.acres or 0),
            last_visit_at=r.last_visit_at,
            last_purchase_at=r.last_purchase_at,
            balance_paise=int(r.balance or 0),
            overdue_paise=int(r.overdue or 0),
            credit_risk=r.risk,
            ltv_paise=facts._paise(r.ltv),
            app_user=bool(r.app_user),
            consent_marketing=bool(r.consent_marketing),
        )
        for r in fetched[:limit]
    ]
    return FarmerDirectoryOut(
        filters=scope.echo(),
        items=items,
        next_cursor=encode_offset(offset + limit) if len(fetched) > limit else None,
        total=int(total or 0),
    )


# --------------------------------------------------------------------------- 360
async def farmer_360(session: AsyncSession, scope: Scope, farmer_id: uuid.UUID) -> Farmer360Out:
    tid = scope.tenant_id
    found = await session.execute(
        select(Farmer, Village)
        .join(Village, Village.id == Farmer.village_id)
        .where(Farmer.id == farmer_id, *scope.farmer_filters())
    )
    row = found.first()
    if row is None:
        raise NotFoundError("Farmer not found.")
    farmer, village = row
    f = scope.filters
    _, end = f.bounds
    settings = await tenant_settings(session, tid)
    due_days = credit_settings(settings).credit_due_days
    registered_by_name = (
        await session.scalar(select(User.name).where(User.id == farmer.registered_by))
        if farmer.registered_by
        else None
    )

    # Farms, crop plots.
    farms = (
        (
            await session.execute(
                select(Farm)
                .where(Farm.farmer_id == farmer.id, Farm.deleted_at.is_(None))
                .order_by(Farm.created_at, Farm.id)
            )
        )
        .scalars()
        .all()
    )
    plot_rows = await session.execute(
        select(CropPlot, Crop.code, Crop.name)
        .join(Crop, Crop.id == CropPlot.crop_id)
        .where(CropPlot.farm_id.in_([fm.id for fm in farms]), CropPlot.deleted_at.is_(None))
        .order_by(CropPlot.sowing_date, CropPlot.id)
    )
    plots: dict[uuid.UUID, list[FarmerCropPlotOut]] = defaultdict(list)
    for plot, code, name in plot_rows:
        plots[plot.farm_id].append(
            FarmerCropPlotOut(
                id=plot.id,
                crop_id=plot.crop_id,
                crop_code=code,
                crop_name=name,
                variety=plot.variety,
                season=plot.season,
                sowing_date=plot.sowing_date,
                stage=plot.stage,
                expected_harvest=plot.expected_harvest,
                area_acres=float(plot.area_acres) if plot.area_acres is not None else None,
            )
        )
    farm_out = [
        FarmerFarmOut(
            id=fm.id,
            name=fm.name,
            survey_no=fm.survey_no,
            area_acres=float(fm.area_acres),
            area_acres_computed=(
                float(fm.area_acres_computed) if fm.area_acres_computed is not None else None
            ),
            soil=fm.soil,
            irrigation=fm.irrigation,
            boundary=json.loads(fm.boundary_geojson) if fm.boundary_geojson else None,
            centroid=(
                {"type": "Point", "coordinates": [fm.centroid_lon, fm.centroid_lat]}
                if fm.centroid_lon is not None
                else None
            ),
            crop_plots=plots.get(fm.id, []),
        )
        for fm in farms
    ]

    # Visits (newest first).
    visit_rows = await session.execute(
        select(Visit, User.name)
        .join(User, User.id == Visit.officer_id)
        .where(Visit.farmer_id == farmer.id, Visit.deleted_at.is_(None), Visit.tenant_id == tid)
        .order_by(Visit.checkin_at.desc(), Visit.id)
        .limit(HISTORY_LIMIT)
    )
    visits = [
        FarmerVisitOut(
            id=v.id,
            officer_id=v.officer_id,
            officer_name=name,
            purpose=v.purpose,
            checkin_at=v.checkin_at,
            checkout_at=v.checkout_at,
            status=v.status,
            score=v.score,
            confirmed=v.confirmed_at is not None,
            crop_stage=v.crop_stage,
        )
        for v, name in visit_rows
    ]

    # Orders (newest first).
    line_count = (
        select(func.count())
        .where(OrderLine.order_id == Order.id, OrderLine.deleted_at.is_(None))
        .correlate(Order)
        .scalar_subquery()
    )
    order_rows = await session.execute(
        select(Order, line_count)
        .where(Order.farmer_id == farmer.id, Order.deleted_at.is_(None), Order.tenant_id == tid)
        .order_by(func.coalesce(Order.placed_at, Order.created_at).desc(), Order.id)
        .limit(HISTORY_LIMIT)
    )
    orders = [
        FarmerOrderOut(
            id=o.id,
            store_id=o.store_id,
            channel=o.channel,
            status=o.status,
            total_paise=o.total_paise,
            placed_at=o.placed_at,
            invoice_no=o.invoice_no,
            lines=int(n or 0),
        )
        for o, n in order_rows
    ]

    # Khata.
    entries = (
        (
            await session.execute(
                select(KhataEntry).where(
                    KhataEntry.farmer_id == farmer.id,
                    KhataEntry.tenant_id == tid,
                    KhataEntry.created_at < end,
                )
            )
        )
        .scalars()
        .all()
    )
    book = credit_book(entries, f.to, due_days, until=end)
    balance = sum(e.signed_paise for e in entries)
    next_due = await session.scalar(
        select(func.min(KhataEntry.due_date)).where(
            KhataEntry.farmer_id == farmer.id,
            KhataEntry.type == EntryType.DEBIT.value,
            KhataEntry.due_date >= f.to,
        )
    )
    limits = await session.execute(
        select(CreditLimit.store_id, CreditLimit.limit_paise).where(
            CreditLimit.farmer_id == farmer.id, CreditLimit.deleted_at.is_(None)
        )
    )
    last_payment = await session.scalar(
        select(func.max(func.coalesce(Payment.paid_at, Payment.created_at))).where(
            Payment.farmer_id == farmer.id,
            Payment.deleted_at.is_(None),
            Payment.mode != PaymentMode.CREDIT.value,
        )
    )

    # Consent (append-only history; latest row per purpose is the state).
    consents = (
        (
            await session.execute(
                select(ConsentRecord)
                .where(
                    ConsentRecord.tenant_id == tid,
                    ConsentRecord.subject_type == ConsentSubject.FARMER.value,
                    ConsentRecord.subject_id == farmer.id,
                )
                .order_by(ConsentRecord.created_at, ConsentRecord.id)
            )
        )
        .scalars()
        .all()
    )
    current: dict[str, bool] = {}
    history = []
    for c in consents:
        current[c.purpose] = c.granted
        history.append(
            ConsentEventOut(
                purpose=c.purpose,
                granted=c.granted,
                at=c.granted_at or c.withdrawn_at or c.created_at,
                version=c.version,
                channel=c.channel,
            )
        )

    # App usage proxy, LTV, last activity, active.
    window_start = ist_start(f.to - timedelta(days=ACTIVE_WINDOW_DAYS - 1))
    sessions: list[datetime] = []
    if farmer.user_id is not None:
        sessions = list(
            (
                await session.execute(
                    select(RefreshToken.created_at).where(
                        RefreshToken.user_id == farmer.user_id,
                        RefreshToken.tenant_id == tid,
                        RefreshToken.created_at < end,
                    )
                )
            ).scalars()
        )
    lines = facts.tenant_sales_lines(tid)
    ltv_raw = await session.scalar(
        select(func.sum(lines.c.net - lines.c.cost)).where(
            lines.c.farmer_id == farmer.id, lines.c.sold_at < end
        )
    )
    last_visit_at = await session.scalar(
        select(func.max(Visit.checkin_at)).where(
            Visit.farmer_id == farmer.id, Visit.deleted_at.is_(None), Visit.checkin_at < end
        )
    )
    last_purchase_at = await session.scalar(
        select(func.max(lines.c.sold_at)).where(
            lines.c.farmer_id == farmer.id, lines.c.sold_at < end
        )
    )
    verified_days = (
        await session.execute(
            select(Visit.checkin_at).where(
                Visit.farmer_id == farmer.id,
                Visit.deleted_at.is_(None),
                Visit.score >= 70,
                Visit.checkin_at >= window_start,
                Visit.checkin_at < end,
            )
        )
    ).scalars()
    active = farmer.id in active_farmers(
        f.to,
        purchases=[(farmer.id, to_ist_date(last_purchase_at))] if last_purchase_at else [],
        verified_visits=[(farmer.id, to_ist_date(t)) for t in verified_days],
        app_sessions=[(farmer.id, to_ist_date(t)) for t in sessions],
    )

    return Farmer360Out(
        filters=scope.echo(),
        profile=FarmerProfileOut(
            id=farmer.id,
            name=farmer.name,
            phone=farmer.phone,
            phone_verified=farmer.phone_verified,
            language=farmer.language,
            landmark=farmer.landmark,
            source=farmer.source,
            village_id=village.id,
            village=village.name,
            district=village.district,
            store_id=village.store_id,
            registered_by=farmer.registered_by,
            registered_by_name=registered_by_name,
            created_at=farmer.created_at,
            updated_at=farmer.updated_at,
        ),
        farms=farm_out,
        visits=visits,
        diagnoses=[],
        orders=orders,
        khata=KhataSummaryOut(
            balance_paise=balance,
            overdue_paise=book.overdue_paise,
            overdue_buckets=book.buckets,
            next_due_date=next_due,
            credit_limits=[
                {"store_id": str(store_id), "limit_paise": int(limit)} for store_id, limit in limits
            ],
            last_payment_at=last_payment,
            credit_risk=credit_risk(book.buckets),
        ),
        consent=ConsentOut(current=current, history=history),
        app_usage=AppUsageOut(
            has_app_login=farmer.user_id is not None,
            last_session_at=max(sessions) if sessions else None,
            sessions_last_60_days=sum(1 for t in sessions if t >= window_start),
            proxy=APP_USAGE_PROXY,
        ),
        ltv_paise=facts._paise(ltv_raw),
        last_visit_at=last_visit_at,
        last_purchase_at=last_purchase_at,
        active=active,
        notes={"diagnoses": "pending_m6_diagnosis"},
    )


__all__ = ["SORTS", "decode_offset", "directory", "encode_offset", "farmer_360", "mask_phone"]
