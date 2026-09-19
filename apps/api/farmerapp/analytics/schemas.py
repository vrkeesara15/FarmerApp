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
        description="Always empty until AN-006 (crop health map, P1)."
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
    reason: str | None = Field(description="The officer's reason (VV-008); null until it exists.")


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
    ltv_paise: int
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
    ltv_paise: int
    last_visit_at: datetime | None
    last_purchase_at: datetime | None
    active: bool
    notes: dict[str, str]


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
    credit_outstanding_paise: int
    credit_overdue_paise: int
    last_day_close: LastDayCloseOut | None


class StoreListOut(BaseModel):
    filters: FiltersOut
    items: list[StoreRow]


class CategorySalesOut(BaseModel):
    category: str
    net_sales_paise: int
    gross_margin_paise: int
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


class StockSummaryOut(BaseModel):
    value_paise: int
    skus_in_stock: int
    turns: float | None = Field(description="COGS in the range / current stock value at cost.")
    turns_annualised: float | None
    stockouts: list[StockoutOut] = Field(description="SKUs the store has stocked, now at zero.")


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
    brand_split: BrandSplitOut
    stock: StockSummaryOut
    credit_book: CreditBookOut
    day_closes: list[StoreDayCloseOut]
    pnl: list[PnlMonthOut]
    pnl_opex_included: bool = False
    pnl_note: str
