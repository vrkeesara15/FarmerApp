"""WC-004 stores list (C40) and store detail with P&L by month (C41); AN-005 groundwork.

Per store over the range: net sales (pre-GST, after discounts), COGS (sold batch cost),
gross margin, own-brand share, orders, current stock value at cost, credit outstanding and
overdue as of ``to`` and the last day close (variance). The detail adds sales by category,
own-brand vs multi-brand, stock turns and stockouts, the credit book ageing, the day-close
history and the P&L by month:

    gross sales - discounts = net sales; net sales - COGS = gross margin;
    gross margin - write-offs (damage at batch cost) = contribution.

Operating expenses (rent, salaries, power, transport) are **out of scope**: there is no
expense ledger in P0, so ``pnl_opex_included`` is ``false`` and ``pnl_note`` says so
(``operating_expenses_out_of_scope``). Months cut by the range are ``partial``.

Stock turns = COGS in the range / current stock value at cost (annualised: x 365 / days).
A stockout is a SKU the store has stocked (a batch exists) whose on-hand quantity is zero.
``days_out_of_stock`` replays the append-only stock ledger backwards from today's on-hand
(``stock_movement`` is never updated, so on-hand at the end of an earlier IST day is the
on-hand now minus every movement after it) and counts the days in the range at zero, from
the day the store first stocked the SKU.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics import facts
from farmerapp.analytics.filters import Scope, StoreInfo
from farmerapp.analytics.kpi import credit_book, ratio
from farmerapp.analytics.owner_home import tenant_settings
from farmerapp.analytics.schemas import (
    BrandSalesOut,
    BrandSplitOut,
    CategorySalesOut,
    CreditBookOut,
    LastDayCloseOut,
    PnlMonthOut,
    StockoutOut,
    StockSummaryOut,
    StoreDayCloseOut,
    StoreDetailOut,
    StoreListOut,
    StoreRow,
)
from farmerapp.api.errors import NotFoundError
from farmerapp.catalog.models import Product, Sku
from farmerapp.khata.ledger import credit_settings
from farmerapp.khata.models import KhataEntry
from farmerapp.payments.models import DayClose

PNL_NOTE = "operating_expenses_out_of_scope"


def _pct(margin: int, net: int) -> float | None:
    r = ratio(margin, net)
    return None if r is None else round(r, 4)


def _single(scope: Scope, store: StoreInfo) -> Scope:
    return Scope(
        actor=scope.actor,
        filters=scope.filters,
        level=scope.level,
        stores=(store,),
        officers=tuple(o for o in scope.officers if o.store_id == store.id),
        store_ids=frozenset({store.id}),
        officer_ids=scope.officer_ids,
        own_officer_id=scope.own_officer_id,
        crop_id=scope.crop_id,
    )


async def _last_day_closes(
    session: AsyncSession, scope: Scope, store_ids: list[uuid.UUID]
) -> dict[uuid.UUID, DayClose]:
    if not store_ids:
        return {}
    rows = (
        (
            await session.execute(
                select(DayClose)
                .where(
                    DayClose.tenant_id == scope.tenant_id,
                    DayClose.deleted_at.is_(None),
                    DayClose.store_id.in_(store_ids),
                    DayClose.business_date <= scope.filters.to,
                )
                .order_by(DayClose.store_id, DayClose.business_date.desc())
                .distinct(DayClose.store_id)
            )
        )
        .scalars()
        .all()
    )
    return {r.store_id: r for r in rows}


async def _range_variance(
    session: AsyncSession, scope: Scope, store_ids: list[uuid.UUID]
) -> dict[uuid.UUID, int]:
    """Summed day-close variance per store over the range (AN-005 day-close variance)."""
    if not store_ids:
        return {}
    rows = await session.execute(
        select(DayClose.store_id, func.sum(DayClose.variance_paise))
        .where(
            DayClose.tenant_id == scope.tenant_id,
            DayClose.deleted_at.is_(None),
            DayClose.store_id.in_(store_ids),
            DayClose.business_date >= scope.filters.from_,
            DayClose.business_date <= scope.filters.to,
        )
        .group_by(DayClose.store_id)
    )
    return {r[0]: int(r[1] or 0) for r in rows}


async def store_list(session: AsyncSession, scope: Scope) -> StoreListOut:
    f = scope.filters
    start, end = f.bounds
    due_days = credit_settings(await tenant_settings(session, scope.tenant_id)).credit_due_days
    ids = [s.id for s in scope.stores]
    sales = await facts.sales_aggregate(session, scope, start, end, ["store_id", "own_brand"])
    net: dict[uuid.UUID, int] = defaultdict(int)
    own: dict[uuid.UUID, int] = defaultdict(int)
    cost: dict[uuid.UUID, int] = defaultdict(int)
    for r in sales:
        sid = r.keys["store_id"]
        net[sid] += r.net_paise
        cost[sid] += r.cost_paise
        if r.keys["own_brand"]:
            own[sid] += r.net_paise
    order_counts = {
        r.keys["store_id"]: r.orders
        for r in await facts.sales_aggregate(session, scope, start, end, ["store_id"])
    }
    stock = await facts.stock_value_by_store(session, scope.tenant_id, ids)
    stockouts = await facts.stockouts_by_store(session, scope.tenant_id, ids)
    entries = await facts.khata_entries(session, scope, end)
    by_store: dict[uuid.UUID, list[KhataEntry]] = defaultdict(list)
    for e in entries:
        by_store[e.store_id].append(e)
    closes = await _last_day_closes(session, scope, ids)
    variance = await _range_variance(session, scope, ids)
    items = []
    for s in scope.stores:
        book = credit_book(by_store.get(s.id, []), f.to, due_days, until=end)
        close = closes.get(s.id)
        margin = net[s.id] - cost[s.id]
        turns = ratio(cost[s.id], stock.get(s.id, 0))
        items.append(
            StoreRow(
                id=s.id,
                code=s.code,
                name=s.name,
                district=s.district,
                cluster_id=s.cluster_id,
                net_sales_paise=net[s.id],
                cogs_paise=cost[s.id],
                gross_margin_paise=margin,
                gross_margin_pct=_pct(margin, net[s.id]),
                own_brand_share=_pct(own[s.id], net[s.id]),
                orders=order_counts.get(s.id, 0),
                stock_value_paise=stock.get(s.id, 0),
                stock_turns_annualised=(None if turns is None else round(turns * 365 / f.days, 4)),
                stockouts=stockouts.get(s.id, 0),
                credit_outstanding_paise=book.outstanding_paise,
                credit_overdue_paise=book.overdue_paise,
                credit_overdue_buckets=book.buckets,
                last_day_close=(
                    LastDayCloseOut(
                        business_date=close.business_date,
                        variance_paise=close.variance_paise,
                        status=close.status,
                    )
                    if close is not None
                    else None
                ),
                day_close_variance_paise=variance.get(s.id, 0),
            )
        )
    return StoreListOut(filters=scope.echo(), items=items)


async def _stockout_days(
    session: AsyncSession,
    scope: Scope,
    store_id: uuid.UUID,
    on_hand: dict[uuid.UUID, tuple[Decimal, int, date]],
) -> dict[uuid.UUID, int]:
    """IST days in the range on which each SKU was out of stock (AN-005 stockouts per SKU).

    The stock ledger is append-only, so on-hand at the end of IST day *d* is the on-hand now
    minus every movement after *d*. Walking the range backwards from the end therefore needs
    one grouped query and no per-day state in SQL.
    """
    f = scope.filters
    start, _ = f.bounds
    deltas: dict[uuid.UUID, dict[date, Decimal]] = defaultdict(dict)
    after_range: dict[uuid.UUID, Decimal] = defaultdict(Decimal)
    for sku_id, day, qty in await facts.stock_deltas(session, scope.tenant_id, store_id, start):
        if day > f.to:
            after_range[sku_id] += qty
        else:
            deltas[sku_id][day] = deltas[sku_id].get(day, Decimal(0)) + qty
    out: dict[uuid.UUID, int] = {}
    for sku_id, (qty_now, _value, first_day) in on_hand.items():
        running = qty_now - after_range.get(sku_id, Decimal(0))  # end of `to`
        days = 0
        day = f.to
        while day >= f.from_:
            if day >= first_day and running <= 0:
                days += 1
            running -= deltas.get(sku_id, {}).get(day, Decimal(0))
            day -= timedelta(days=1)
        if days:
            out[sku_id] = days
    return out


async def _stockout_rows(
    session: AsyncSession,
    on_hand: dict[uuid.UUID, tuple[Decimal, int, date]],
    days_out: dict[uuid.UUID, int],
) -> list[StockoutOut]:
    """One row per SKU out of stock now or at any point in the range, worst first."""
    sku_ids = {s for s, (qty, _, _) in on_hand.items() if qty <= 0} | set(days_out)
    if not sku_ids:
        return []
    names = await session.execute(
        select(Sku.id, Product.name, Sku.pack_size_value, Sku.pack_size_unit)
        .join(Product, Product.id == Sku.product_id)
        .where(Sku.id.in_(sku_ids))
    )
    rows = [
        StockoutOut(
            sku_id=i,
            product_name=n,
            pack=f"{v.normalize():f} {u}",
            days_out_of_stock=days_out.get(i, 0),
            currently_out=on_hand.get(i, (Decimal(0), 0, date.min))[0] <= 0,
        )
        for i, n, v, u in names
    ]
    rows.sort(key=lambda r: (-r.days_out_of_stock, not r.currently_out, r.product_name, r.pack))
    return rows


def _months(first: date, last: date) -> list[tuple[date, date, date, bool]]:
    """``(month start, range start in month, range end in month, partial)`` per month."""
    out = []
    month = first.replace(day=1)
    while month <= last:
        nxt = (month + timedelta(days=32)).replace(day=1)
        lo, hi = max(first, month), min(last, nxt - timedelta(days=1))
        out.append((month, lo, hi, lo != month or hi != nxt - timedelta(days=1)))
        month = nxt
    return out


async def store_detail(session: AsyncSession, scope: Scope, store_id: uuid.UUID) -> StoreDetailOut:
    store = next((s for s in scope.stores if s.id == store_id), None)
    if store is None:
        raise NotFoundError("Store not found.")
    one = _single(scope, store)
    f = one.filters
    start, end = f.bounds
    due_days = credit_settings(await tenant_settings(session, one.tenant_id)).credit_due_days

    by_category = await facts.sales_aggregate(session, one, start, end, ["category"])
    by_brand = await facts.sales_aggregate(session, one, start, end, ["own_brand"])
    by_brand_name = await facts.sales_aggregate(session, one, start, end, ["brand", "own_brand"])
    by_month = await facts.sales_aggregate(session, one, start, end, ["month"])
    net = sum(r.net_paise for r in by_brand)
    cogs = sum(r.cost_paise for r in by_brand)
    own = next((r for r in by_brand if r.keys["own_brand"]), None)
    multi = next((r for r in by_brand if not r.keys["own_brand"]), None)

    # Stock: value, SKUs in stock, and the days each SKU spent at zero over the range.
    on_hand = await facts.stock_on_hand(session, one.tenant_id, store.id)
    value = sum(v for _, v, _ in on_hand.values())
    in_stock = sum(1 for qty, _, _ in on_hand.values() if qty > 0)
    days_out = await _stockout_days(session, one, store.id, on_hand)
    stockouts = await _stockout_rows(session, on_hand, days_out)
    turns = ratio(cogs, value)

    # Credit book.
    entries = (
        (
            await session.execute(
                select(KhataEntry).where(
                    KhataEntry.tenant_id == one.tenant_id,
                    KhataEntry.store_id == store.id,
                    KhataEntry.created_at < end,
                    *one.farmer_column_filters(KhataEntry.farmer_id),
                )
            )
        )
        .scalars()
        .all()
    )
    book = credit_book(entries, f.to, due_days, until=end)

    # Day closes in the range.
    closes = (
        (
            await session.execute(
                select(DayClose)
                .where(
                    DayClose.tenant_id == one.tenant_id,
                    DayClose.store_id == store.id,
                    DayClose.deleted_at.is_(None),
                    DayClose.business_date >= f.from_,
                    DayClose.business_date <= f.to,
                )
                .order_by(DayClose.business_date.desc())
            )
        )
        .scalars()
        .all()
    )

    # P&L by month.
    write_offs: dict[date, int] = defaultdict(int)
    for day, paise in await facts.write_offs(session, one.tenant_id, store.id, start, end):
        write_offs[day.replace(day=1)] += paise
    months = {r.keys["month"]: r for r in by_month}
    pnl = []
    for month, _lo, _hi, partial in _months(f.from_, f.to):
        row = months.get(month)
        gross = row.gross_paise if row else 0
        disc = row.discount_paise if row else 0
        m_net = row.net_paise if row else 0
        m_cogs = row.cost_paise if row else 0
        margin = m_net - m_cogs
        wo = write_offs.get(month, 0)
        pnl.append(
            PnlMonthOut(
                month=month.strftime("%Y-%m"),
                partial=partial,
                gross_sales_paise=gross,
                discounts_paise=disc,
                net_sales_paise=m_net,
                cogs_paise=m_cogs,
                gross_margin_paise=margin,
                gross_margin_pct=_pct(margin, m_net),
                write_offs_paise=wo,
                contribution_paise=margin - wo,
            )
        )

    return StoreDetailOut(
        filters=scope.echo(),
        id=store.id,
        code=store.code,
        name=store.name,
        district=store.district,
        cluster_id=store.cluster_id,
        net_sales_paise=net,
        cogs_paise=cogs,
        gross_margin_paise=net - cogs,
        gross_margin_pct=_pct(net - cogs, net),
        sales_by_category=sorted(
            (
                CategorySalesOut(
                    category=r.keys["category"],
                    net_sales_paise=r.net_paise,
                    gross_margin_paise=r.margin_paise,
                    share=_pct(r.net_paise, net),
                )
                for r in by_category
            ),
            key=lambda c: (-c.net_sales_paise, c.category),
        ),
        sales_by_brand=sorted(
            (
                BrandSalesOut(
                    brand=r.keys["brand"],
                    own_brand=bool(r.keys["own_brand"]),
                    net_sales_paise=r.net_paise,
                    gross_margin_paise=r.margin_paise,
                    gross_margin_pct=_pct(r.margin_paise, r.net_paise),
                    share=_pct(r.net_paise, net),
                )
                for r in by_brand_name
            ),
            key=lambda b: (-b.net_sales_paise, b.brand),
        ),
        brand_split=BrandSplitOut(
            own_brand_paise=own.net_paise if own else 0,
            multi_brand_paise=multi.net_paise if multi else 0,
            own_brand_share=_pct(own.net_paise if own else 0, net),
            own_brand_margin_paise=own.margin_paise if own else 0,
            multi_brand_margin_paise=multi.margin_paise if multi else 0,
        ),
        stock=StockSummaryOut(
            value_paise=value,
            skus_in_stock=in_stock,
            turns=None if turns is None else round(turns, 4),
            turns_annualised=None if turns is None else round(turns * 365 / f.days, 4),
            stockout_days=sum(days_out.values()),
            stockouts=stockouts,
        ),
        credit_book=CreditBookOut(
            outstanding_paise=book.outstanding_paise,
            overdue_paise=book.overdue_paise,
            buckets=book.buckets,
            accounts=book.accounts,
        ),
        day_closes=[
            StoreDayCloseOut(
                business_date=c.business_date,
                cash_expected_paise=c.cash_expected_paise,
                cash_counted_paise=c.cash_counted_paise,
                variance_paise=c.variance_paise,
                status=c.status,
                variance_flagged=c.variance_flagged,
            )
            for c in closes
        ],
        pnl=pnl,
        pnl_opex_included=False,
        pnl_note=PNL_NOTE,
    )


__all__ = ["PNL_NOTE", "store_detail", "store_list"]
