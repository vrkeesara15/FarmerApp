"""Response shapes of ``/v1/analytics/*`` (the console's C10, C20-C22, C30-C31, C40-C41).

Money is integer paise, ratios floats in ``[0, 1]`` (``null`` when undefined), durations
seconds, distances km, timestamps UTC (RFC 3339), days IST dates. Every response carries the
applied ``filters`` (AN-011).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

from farmerapp.analytics.filters import FiltersOut
from farmerapp.campaigns.segments import Segment

Granularity = Literal["day", "week"]
Band = Literal["green", "amber", "red", "none"]


class SeriesPoint(BaseModel):
    start: date
    end: date = Field(description="Last day of the bucket (inclusive).")
    value: float | None


class KpiOut(BaseModel):
    key: str = Field(
        description="`revenue`, `own_brand_share`, `credit_outstanding`, `credit_overdue`, "
        "`verified_visits`, `active_farmers`, `open_flags`."
    )
    unit: Literal["paise", "ratio", "count"]
    value: float | None
    target: float | None = Field(
        description="From the tenant setting `targets` (additive KPIs scaled to the range)."
    )
    last_year: float | None = Field(description="Same period last year.")
    trend: list[SeriesPoint]


class StoreMapItem(BaseModel):
    id: uuid.UUID
    code: str
    name: str
    district: str
    cluster_id: uuid.UUID | None
    lat: float | None
    lon: float | None
    revenue_paise: int
    own_brand_share: float | None
    overdue_paise: int
    score: int | None = Field(description="Performance score 0-100 (see `band`).")
    band: Band


class OfficerRankOut(BaseModel):
    id: uuid.UUID
    name: str
    store_id: uuid.UUID | None
    verified_visits: int
    duty_days: int
    verified_visits_per_day: float | None


class FlagOut(BaseModel):
    id: uuid.UUID
    rule: str
    severity: str
    title: str
    opened_at: datetime
    officer_id: uuid.UUID | None = None
    store_id: uuid.UUID | None = None
    farmer_id: uuid.UUID | None = None


class OwnerHomeSeries(BaseModel):
    revenue: list[SeriesPoint]
    revenue_last_year: list[SeriesPoint]
    own_brand_share: list[SeriesPoint]


class OwnerHomeOut(BaseModel):
    filters: FiltersOut
    granularity: Granularity
    kpis: list[KpiOut]
    credit_overdue_buckets: dict[str, int] = Field(
        description="`0_30` / `31_60` / `61_90` / `90_plus` paise as of `to`."
    )
    series: OwnerHomeSeries
    stores: list[StoreMapItem]
    officers_top: list[OfficerRankOut]
    officers_bottom: list[OfficerRankOut]
    high_severity_flags: list[FlagOut]
    crop_health_alerts: list[dict[str, Any]] = Field(
        description="AN-006: the tenant's active outbreak alerts (FM-009 / DX-013), newest week "
        "first, at most five. Each item carries the fields of `OutbreakAlertOut` plus `title` "
        "and `problem` for the card; district level only (AN-014). `GET /v1/alerts` and "
        "`GET /v1/analytics/crop-health` are the full reads."
    )
    notes: dict[str, str]


# --------------------------------------------------------------------------- field team
class ScorecardRow(BaseModel):
    officer_id: uuid.UUID
    name: str
    store_id: uuid.UUID | None
    cluster_id: uuid.UUID | None
    rank: int
    duty_days: int
    visits: int
    verified_visits: int
    verified_visits_per_day: float | None
    unique_farmers_reached: int
    new_registrations: int
    confirmation_rate: float | None
    avg_time_on_farm_s: int | None = Field(description="Time on farm / verified visits.")
    time_on_farm_s: int
    km_per_day: float | None = Field(
        description="Duty km / duty days. Null for callers who may not see tracks (SPEC 2.6)."
    )
    conversion_rate: float | None
    converted_farmers: int
    visited_farmers: int
    collections_paise: int
    flags: int
    trend: list[SeriesPoint] = Field(description="Verified visits per week (sparkline).")


class FieldTeamOut(BaseModel):
    filters: FiltersOut
    location_visible: bool = Field(description="False: `km_per_day` is withheld (SPEC 2.6).")
    items: list[ScorecardRow]


class DutyDayOut(BaseModel):
    day: date
    start_at: datetime
    end_at: datetime | None
    km: float | None
    visits: int
    verified_visits: int
    time_on_farm_s: int


class OfficerVisitOut(BaseModel):
    id: uuid.UUID
    farmer_id: uuid.UUID
    farmer_name: str
    checkin_at: datetime
    checkout_at: datetime | None
    status: str
    score: int | None
    purpose: str


class OfficerProfileOut(BaseModel):
    filters: FiltersOut
    id: uuid.UUID
    name: str
    phone: str
    status: str
    store_id: uuid.UUID | None
    store_name: str | None
    cluster_id: uuid.UUID | None
    on_duty: bool
    location_visible: bool
    scorecard: ScorecardRow
    duty_days: list[DutyDayOut]
    recent_visits: list[OfficerVisitOut]
    sales_net_paise: int = Field(
        default=0,
        description="Net sales of the orders the officer placed in the range (fulfilled; "
        "FA-024 shows the same figure in the officer's app).",
    )
    sales_orders: int = Field(default=0, description="Those orders.")


# --------------------------------------------------------------------------- day replay
class GeoJsonMultiLineString(BaseModel):
    type: Literal["MultiLineString"] = "MultiLineString"
    coordinates: list[list[list[float]]] = Field(description="[[[lon, lat], ...], ...]")


class ReplayPoint(BaseModel):
    ts: datetime
    lat: float
    lon: float
    accuracy_m: float


class StopOut(BaseModel):
    lat: float
    lon: float
    start: datetime
    end: datetime
    duration_s: int


class GapOut(BaseModel):
    start: datetime
    end: datetime
    duration_s: int
    duty_session_id: uuid.UUID
    reason: str | None = Field(
        description="The officer's reason (VV-008): network | personal_break | vehicle | "
        "other; null while not given."
    )
    id: uuid.UUID | None = Field(
        default=None,
        description="Stable gap id (VV-008 `POST /v1/me/gaps/{gap_id}/reason`).",
    )
    note: str | None = Field(default=None, description="The officer's note with the reason.")


class ProofItemOut(BaseModel):
    kind: Literal["geofence", "photo", "confirmation", "duration", "integrity"]
    satisfied: bool
    points: int
    max_points: int


class ReplayVisitOut(BaseModel):
    id: uuid.UUID
    farmer_id: uuid.UUID
    farmer_name: str
    purpose: str
    checkin_at: datetime
    checkout_at: datetime | None
    duration_s: int | None
    lat: float
    lon: float
    geofence_result: str
    status: str
    colour: Literal["green", "amber", "red", "grey"]
    score: int | None
    score_components: dict[str, int]
    proof: list[ProofItemOut]
    confirmed_at: datetime | None
    photos: int


class TimelineEvent(BaseModel):
    ts: datetime
    type: Literal[
        "duty_start", "duty_end", "visit_checkin", "visit_checkout", "stop", "gap_start", "gap_end"
    ]
    ref_id: uuid.UUID | None = None
    detail: dict[str, Any] = Field(default_factory=dict)


class DutySessionBrief(BaseModel):
    id: uuid.UUID
    start_at: datetime
    end_at: datetime | None
    end_reason: str | None
    km: float | None


class DayReplayOut(BaseModel):
    filters: FiltersOut
    officer_id: uuid.UUID
    officer_name: str
    date: date
    duty_sessions: list[DutySessionBrief]
    km: float
    track: GeoJsonMultiLineString
    points: list[ReplayPoint] = Field(description="Kept points in time order (playback).")
    stops: list[StopOut]
    gaps: list[GapOut]
    visits: list[ReplayVisitOut]
    timeline: list[TimelineEvent]


# --------------------------------------------------------------------------- farmers
class FarmerRow(BaseModel):
    id: uuid.UUID
    name: str
    phone_masked: str = Field(description="`******1234` (SPEC AN-014: full phone on the 360).")
    village_id: uuid.UUID
    village: str
    district: str
    store_id: uuid.UUID | None
    registered_by: uuid.UUID | None
    crops: list[str] = Field(description="Crop codes of the live crop plots.")
    stages: list[str]
    acres: float
    last_visit_at: datetime | None
    last_purchase_at: datetime | None
    balance_paise: int
    overdue_paise: int
    credit_risk: Literal["low", "medium", "high"]
    ltv_paise: int = Field(description="SPEC 5.2 farmer LTV: cumulative gross margin.")
    spend_paise: int = Field(default=0, description="Cumulative net sales to the farmer.")
    orders: int = Field(default=0, description="Fulfilled orders, all time.")
    churn_risk: bool = Field(
        default=False,
        description="AN-004: bought before, but no purchase and no visit in the churn window.",
    )
    app_user: bool
    consent_marketing: bool


class FarmerDirectoryOut(BaseModel):
    filters: FiltersOut
    items: list[FarmerRow]
    next_cursor: str | None
    total: int


class FarmerCropPlotOut(BaseModel):
    id: uuid.UUID
    crop_id: uuid.UUID
    crop_code: str
    crop_name: str
    variety: str | None
    season: str
    sowing_date: date
    stage: str | None
    expected_harvest: date | None
    area_acres: float | None


class FarmerFarmOut(BaseModel):
    id: uuid.UUID
    name: str | None
    survey_no: str | None
    area_acres: float
    area_acres_computed: float | None
    soil: str | None
    irrigation: str | None
    boundary: dict[str, Any] | None = Field(description="GeoJSON Polygon.")
    centroid: dict[str, Any] | None = Field(description="GeoJSON Point.")
    crop_plots: list[FarmerCropPlotOut]


class FarmerVisitOut(BaseModel):
    id: uuid.UUID
    officer_id: uuid.UUID
    officer_name: str
    purpose: str
    checkin_at: datetime
    checkout_at: datetime | None
    status: str
    score: int | None
    confirmed: bool
    crop_stage: str | None


class FarmerOrderOut(BaseModel):
    id: uuid.UUID
    store_id: uuid.UUID
    channel: str
    status: str
    total_paise: int
    placed_at: datetime | None
    invoice_no: str | None
    lines: int


class KhataSummaryOut(BaseModel):
    balance_paise: int
    overdue_paise: int
    overdue_buckets: dict[str, int]
    next_due_date: date | None
    credit_limits: list[dict[str, Any]] = Field(description="`{store_id, limit_paise}` per store.")
    last_payment_at: datetime | None
    credit_risk: Literal["low", "medium", "high"]


class ConsentEventOut(BaseModel):
    purpose: str
    granted: bool
    at: datetime
    version: str
    channel: str


class ConsentOut(BaseModel):
    current: dict[str, bool] = Field(description="Latest state per purpose (`data`, `marketing`).")
    history: list[ConsentEventOut]


class AppUsageOut(BaseModel):
    has_app_login: bool
    last_session_at: datetime | None
    sessions_last_60_days: int
    proxy: str = Field(description="How app sessions are measured (refresh-token issuance).")


class ChurnRiskOut(BaseModel):
    """AN-004 churn risk of one farmer, with the numbers behind the flag."""

    at_risk: bool
    window_days: int = Field(description="Quiet for this long counts as churn risk.")
    days_since_last_purchase: int | None
    days_since_last_visit: int | None
    orders: int = Field(description="Fulfilled orders all time (0: never a customer).")


class FarmerProfileOut(BaseModel):
    id: uuid.UUID
    name: str
    phone: str
    phone_verified: bool
    language: str
    landmark: str | None
    source: str
    village_id: uuid.UUID
    village: str
    district: str
    store_id: uuid.UUID | None
    registered_by: uuid.UUID | None
    registered_by_name: str | None
    created_at: datetime
    updated_at: datetime


class Farmer360Out(BaseModel):
    filters: FiltersOut
    profile: FarmerProfileOut
    farms: list[FarmerFarmOut]
    visits: list[FarmerVisitOut]
    diagnoses: list[dict[str, Any]] = Field(description="Empty until the diagnosis engine (M6).")
    orders: list[FarmerOrderOut]
    khata: KhataSummaryOut
    consent: ConsentOut
    app_usage: AppUsageOut
    ltv_paise: int = Field(description="SPEC 5.2 farmer LTV: cumulative gross margin.")
    spend_paise: int = Field(default=0, description="Cumulative net sales to the farmer.")
    last_visit_at: datetime | None
    last_purchase_at: datetime | None
    active: bool
    churn_risk: ChurnRiskOut
    notes: dict[str, str]


# --------------------------------------------------------------------------- AN-004 segments
class SegmentFacetOut(BaseModel):
    key: str = Field(description="Crop code, district, stage, band key or window key.")
    count: int


class SegmentPreviewOut(BaseModel):
    """AN-004: what a segment definition selects inside the caller's role scope."""

    filters: FiltersOut
    definition: Segment
    matched: int = Field(description="Farmers matching every criterion (consent aside).")
    consented: int = Field(description="Of those, with current marketing consent: the reach.")
    excluded_no_consent: int
    app_users: int
    churn_risk: int
    churn_window_days: int
    ltv_paise: int = Field(description="Cumulative gross margin of the segment (SPEC 5.2).")
    spend_paise: int
    by_crop: list[SegmentFacetOut]
    by_district: list[SegmentFacetOut]
    by_stage: list[SegmentFacetOut]
    by_acreage_band: list[SegmentFacetOut]
    by_spend_band: list[SegmentFacetOut]
    by_last_visit: list[SegmentFacetOut]
    by_consent: list[SegmentFacetOut]
    by_app_usage: list[SegmentFacetOut]


class SegmentPreviewIn(BaseModel):
    model_config = {"extra": "forbid"}

    definition: Segment = Field(default_factory=Segment)


class SavedSegmentIn(BaseModel):
    model_config = {"extra": "forbid"}

    name: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    definition: Segment = Field(default_factory=Segment)


class SavedSegmentPatch(BaseModel):
    model_config = {"extra": "forbid"}

    name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    definition: Segment | None = None


class SavedSegmentOut(BaseModel):
    id: uuid.UUID
    name: str
    description: str | None
    definition: Segment
    created_by: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
    last_count: int | None = Field(description="Consented reach when the definition was saved.")
    last_counted_at: datetime | None
    version: int


class SavedSegmentListOut(BaseModel):
    items: list[SavedSegmentOut]


class ChurnRowOut(BaseModel):
    id: uuid.UUID
    name: str
    phone_masked: str
    village: str
    district: str
    store_id: uuid.UUID | None
    registered_by: uuid.UUID | None
    crops: list[str]
    ltv_paise: int
    spend_paise: int
    orders: int
    last_purchase_at: datetime | None
    last_visit_at: datetime | None
    days_since_last_purchase: int | None
    days_since_last_visit: int | None
    balance_paise: int
    overdue_paise: int
    credit_risk: Literal["low", "medium", "high"]
    app_user: bool
    consent_marketing: bool


class ChurnListOut(BaseModel):
    filters: FiltersOut
    window_days: int
    total: int = Field(description="Farmers at risk in scope (the list is capped).")
    items: list[ChurnRowOut]


# --------------------------------------------------------------------------- stores
class LastDayCloseOut(BaseModel):
    business_date: date
    variance_paise: int
    status: str


class StoreRow(BaseModel):
    id: uuid.UUID
    code: str
    name: str
    district: str
    cluster_id: uuid.UUID | None
    net_sales_paise: int
    cogs_paise: int
    gross_margin_paise: int
    gross_margin_pct: float | None
    own_brand_share: float | None
    orders: int
    stock_value_paise: int
    stock_turns_annualised: float | None = Field(
        default=None,
        description="AN-005: COGS over the range / stock value at cost, scaled to a year.",
    )
    stockouts: int = Field(
        default=0, description="SKUs the store has stocked whose on-hand is now zero."
    )
    credit_outstanding_paise: int
    credit_overdue_paise: int
    credit_overdue_buckets: dict[str, int] = Field(
        default_factory=dict,
        description="AN-005 credit book ageing: `0_30` / `31_60` / `61_90` / `90_plus` paise.",
    )
    last_day_close: LastDayCloseOut | None
    day_close_variance_paise: int = Field(
        default=0, description="Sum of the day-close variances in the range (AN-005)."
    )


class StoreListOut(BaseModel):
    filters: FiltersOut
    items: list[StoreRow]


class CategorySalesOut(BaseModel):
    category: str
    net_sales_paise: int
    gross_margin_paise: int
    share: float | None


class BrandSalesOut(BaseModel):
    """AN-005 sales by brand: the product's brand, own-brand or multi-brand."""

    brand: str
    own_brand: bool
    net_sales_paise: int
    gross_margin_paise: int
    gross_margin_pct: float | None
    share: float | None


class BrandSplitOut(BaseModel):
    own_brand_paise: int
    multi_brand_paise: int
    own_brand_share: float | None
    own_brand_margin_paise: int
    multi_brand_margin_paise: int


class StockoutOut(BaseModel):
    sku_id: uuid.UUID
    product_name: str
    pack: str
    days_out_of_stock: int = Field(
        default=0, description="IST days in the range with no stock (from the ledger)."
    )
    currently_out: bool = Field(default=True, description="On-hand is zero as of now.")


class StockSummaryOut(BaseModel):
    value_paise: int
    skus_in_stock: int
    turns: float | None = Field(description="COGS in the range / current stock value at cost.")
    turns_annualised: float | None
    stockout_days: int = Field(default=0, description="SKU-days out of stock over the range.")
    stockouts: list[StockoutOut] = Field(
        description="SKUs the store has stocked that are out of stock now or were during the "
        "range, worst first."
    )


class CreditBookOut(BaseModel):
    outstanding_paise: int
    overdue_paise: int
    buckets: dict[str, int]
    accounts: int


class StoreDayCloseOut(BaseModel):
    business_date: date
    cash_expected_paise: int
    cash_counted_paise: int
    variance_paise: int
    status: str
    variance_flagged: bool


class PnlMonthOut(BaseModel):
    month: str = Field(description="`YYYY-MM`.")
    partial: bool = Field(description="The range covers only part of the month.")
    gross_sales_paise: int
    discounts_paise: int
    net_sales_paise: int
    cogs_paise: int
    gross_margin_paise: int
    gross_margin_pct: float | None
    write_offs_paise: int
    contribution_paise: int = Field(description="Gross margin less write-offs.")


class StoreDetailOut(BaseModel):
    filters: FiltersOut
    id: uuid.UUID
    code: str
    name: str
    district: str
    cluster_id: uuid.UUID | None
    net_sales_paise: int
    cogs_paise: int
    gross_margin_paise: int
    gross_margin_pct: float | None
    sales_by_category: list[CategorySalesOut]
    sales_by_brand: list[BrandSalesOut] = Field(
        default_factory=list, description="AN-005: net sales and margin per brand, biggest first."
    )
    brand_split: BrandSplitOut
    stock: StockSummaryOut
    credit_book: CreditBookOut
    day_closes: list[StoreDayCloseOut]
    pnl: list[PnlMonthOut]
    pnl_opex_included: bool = False
    pnl_note: str
