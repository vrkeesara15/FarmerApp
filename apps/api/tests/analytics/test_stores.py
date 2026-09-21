"""WC-004 stores list and store detail with P&L by month (``Mini`` tenant)."""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest
from httpx import AsyncClient

from farmerapp.stock.models import StockMovement
from tests.analytics.builders import Mini, ist
from tests.analytics.conftest import get
from tests.analytics.test_owner_home import FROM, TO
from tests.analytics.test_owner_home import build as build_home
from tests.authz.conftest import Bearer


async def build(m: Mini) -> None:
    await build_home(m)
    # A sale without a batch: costed at the store's average batch cost of the SKU (500).
    await m.sale("N2", None, ist(date(2026, 8, 6), 11), [("multi", 1, 800)], batch=False)
    await m.write_off("N1", "own", 2, ist(date(2026, 8, 6), 18))
    await m.day_close("N1", date(2026, 8, 8), 5_000, 4_750)
    await m.day_close("N1", date(2026, 8, 9), 1_000, 1_000)
    await m.day_close("N1", date(2026, 7, 9), 1_000, 900)
    m.batches[("N1", "multi")].qty = Decimal(0)  # sold out
    await m.session.flush()


async def test_store_list(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    resp = await get(client, bearer, mini.user("owner"), "/stores", from_=FROM, to=TO)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    stores = {s["code"]: s for s in body["items"]}
    assert list(stores) == ["N1", "N2", "S1"]
    n1 = stores["N1"]
    assert (n1["net_sales_paise"], n1["cogs_paise"], n1["gross_margin_paise"]) == (
        2_520,
        1_900,
        620,
    )
    assert n1["gross_margin_pct"] == pytest.approx(round(620 / 2_520, 4))
    assert n1["own_brand_share"] == pytest.approx(round(1_800 / 2_520, 4))
    assert n1["orders"] == 1
    assert n1["stock_value_paise"] == 7_000  # own 10 x 700; multi sold out
    assert (n1["credit_outstanding_paise"], n1["credit_overdue_paise"]) == (9_000, 6_000)
    # AN-005 on the list: ageing buckets, stock turns, stockouts and the range variance.
    assert n1["credit_overdue_buckets"] == {"0_30": 0, "31_60": 0, "61_90": 6_000, "90_plus": 0}
    days = body["filters"]["days"]
    assert n1["stock_turns_annualised"] == pytest.approx(round(1_900 / 7_000 * 365 / days, 4))
    assert n1["stockouts"] == 1  # the multi-brand SKU is sold out
    assert n1["day_close_variance_paise"] == -250  # 8 Aug -250, 9 Aug 0 (July is outside)
    assert stores["N2"]["stockouts"] == 0
    assert n1["last_day_close"] == {
        "business_date": "2026-08-09",
        "variance_paise": 0,
        "status": "closed",
    }
    n2 = stores["N2"]
    assert (n2["net_sales_paise"], n2["cogs_paise"], n2["orders"]) == (2_400, 1_500, 2)
    assert n2["last_day_close"] is None
    assert stores["S1"]["stock_value_paise"] == 12_000


@pytest.mark.parametrize(
    ("role", "codes"),
    [
        ("accountant", ["N1", "N2", "S1"]),
        ("cluster_head", ["N1", "N2"]),
        ("store_manager", ["N1"]),
    ],
)
async def test_store_list_scope(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str, codes: list[str]
) -> None:
    resp = await get(client, bearer, mini.user(role), "/stores")
    assert [s["code"] for s in resp.json()["items"]] == codes


async def test_store_detail_and_pnl_by_month(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    await build(mini)
    n1 = mini.stores["N1"]
    resp = await get(
        client, bearer, mini.user("owner"), f"/stores/{n1.id}", from_="2026-07-01", to="2026-08-31"
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["code"] == "N1"
    # 3 Aug (2,520 net / 1,900 cost) + 1 July (1,000 / 700).
    assert (body["net_sales_paise"], body["cogs_paise"]) == (3_520, 2_600)
    categories = {c["category"]: c for c in body["sales_by_category"]}
    assert categories["pesticide"]["net_sales_paise"] == 2_800
    assert categories["pesticide"]["gross_margin_paise"] == 700
    assert categories["fungicide"]["net_sales_paise"] == 720
    assert categories["fungicide"]["gross_margin_paise"] == 220
    assert body["sales_by_category"][0]["category"] == "pesticide"
    assert body["brand_split"] == {
        "own_brand_paise": 2_800,
        "multi_brand_paise": 720,
        "own_brand_share": round(2_800 / 3_520, 4),
        "own_brand_margin_paise": 700,
        "multi_brand_margin_paise": 220,
    }
    stock = body["stock"]
    assert stock["value_paise"] == 7_000 and stock["skus_in_stock"] == 1
    assert stock["turns"] == pytest.approx(round(2_600 / 7_000, 4))
    assert stock["turns_annualised"] == pytest.approx(round(2_600 / 7_000 * 365 / 62, 4))
    assert stock["stockouts"] == [
        {
            "sku_id": str(mini.skus["multi"].id),
            "product_name": "Other Shield",
            "pack": "500 ml",
            # The batches were received today, after the range: no day in it counts.
            "days_out_of_stock": 0,
            "currently_out": True,
        }
    ]
    assert stock["stockout_days"] == 0
    # AN-005 sales by brand (own vs multi).
    assert body["sales_by_brand"] == [
        {
            "brand": "FCC",
            "own_brand": True,
            "net_sales_paise": 2_800,
            "gross_margin_paise": 700,
            "gross_margin_pct": round(700 / 2_800, 4),
            "share": round(2_800 / 3_520, 4),
        },
        {
            "brand": "Other",
            "own_brand": False,
            "net_sales_paise": 720,
            "gross_margin_paise": 220,
            "gross_margin_pct": round(220 / 720, 4),
            "share": round(720 / 3_520, 4),
        },
    ]
    assert body["credit_book"] == {
        "outstanding_paise": 9_000,
        "overdue_paise": 6_000,
        # As of 31 Aug the 1 June debit is 91 days overdue.
        "buckets": {"0_30": 0, "31_60": 0, "61_90": 0, "90_plus": 6_000},
        "accounts": 2,
    }
    assert [(d["business_date"], d["variance_paise"]) for d in body["day_closes"]] == [
        ("2026-08-09", 0),
        ("2026-08-08", -250),
        ("2026-07-09", -100),
    ]
    july, august = body["pnl"]
    assert july == {
        "month": "2026-07",
        "partial": False,
        "gross_sales_paise": 1_000,
        "discounts_paise": 0,
        "net_sales_paise": 1_000,
        "cogs_paise": 700,
        "gross_margin_paise": 300,
        "gross_margin_pct": 0.3,
        "write_offs_paise": 0,
        "contribution_paise": 300,
    }
    assert august["gross_sales_paise"] == 2_800
    assert august["discounts_paise"] == 280
    assert august["net_sales_paise"] == 2_520
    assert august["cogs_paise"] == 1_900
    assert august["gross_margin_paise"] == 620
    assert august["write_offs_paise"] == 1_400  # 2 x 700 at batch cost
    assert august["contribution_paise"] == 620 - 1_400
    assert body["pnl_opex_included"] is False
    assert body["pnl_note"] == "operating_expenses_out_of_scope"

    partial = (
        await get(client, bearer, mini.user("owner"), f"/stores/{n1.id}", from_=FROM, to=TO)
    ).json()
    assert [(p["month"], p["partial"]) for p in partial["pnl"]] == [("2026-08", True)]
    assert partial["pnl"][0]["net_sales_paise"] == 2_520


async def test_stockout_days_replay_the_ledger(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    """AN-005: days at zero are counted from the append-only ledger, not from `qty` alone."""
    n1, own = mini.stores["N1"], mini.skus["own"]
    batch = mini.batches[("N1", "own")]
    batch.created_at = ist(date(2026, 8, 1), 8)
    batch.qty = Decimal(4)  # on hand now
    # Sold out on 5 Aug (10 -> 0), restocked on 8 Aug (0 -> 4): 5, 6, 7 August are stockouts.
    await mini.add(
        StockMovement(
            tenant_id=mini.tid,
            store_id=n1.id,
            sku_id=own.id,
            batch_id=batch.id,
            kind="sale",
            qty=Decimal(-10),
            ref_type="order",
            created_at=ist(date(2026, 8, 5), 10),
        ),
        StockMovement(
            tenant_id=mini.tid,
            store_id=n1.id,
            sku_id=own.id,
            batch_id=batch.id,
            kind="receipt",
            qty=Decimal(4),
            ref_type="grn",
            created_at=ist(date(2026, 8, 8), 10),
        ),
    )
    body = (
        await get(
            client,
            bearer,
            mini.user("owner"),
            f"/stores/{n1.id}",
            from_="2026-08-01",
            to="2026-08-10",
        )
    ).json()
    rows = {s["sku_id"]: s for s in body["stock"]["stockouts"]}
    assert rows[str(own.id)]["days_out_of_stock"] == 3
    assert rows[str(own.id)]["currently_out"] is False
    assert body["stock"]["stockout_days"] == 3


@pytest.mark.parametrize(
    ("role", "store", "status"),
    [
        ("store_manager", "N1", 200),
        ("store_manager", "N2", 404),
        ("cluster_head", "N2", 200),
        ("cluster_head", "S1", 404),
        ("accountant", "S1", 200),
        ("auditor", "S1", 200),
        ("o1", "N1", 403),
        ("agronomist", "N1", 403),
        ("farmer_user", "N1", 403),
    ],
)
async def test_store_detail_scope(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str, store: str, status: int
) -> None:
    resp = await get(client, bearer, mini.user(role), f"/stores/{mini.stores[store].id}")
    assert resp.status_code == status


async def test_store_detail_unknown(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    resp = await get(
        client, bearer, mini.user("owner"), "/stores/00000000-0000-0000-0000-000000000000"
    )
    assert resp.status_code == 404
