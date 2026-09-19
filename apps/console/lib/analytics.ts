/**
 * Analytics read API (M4: AN-001 .. AN-003, AN-011, WC-001 .. WC-004). Shapes mirror the
 * `/v1/analytics/*` schemas of apps/api/openapi.yaml (docs/prs/M4-analytics-api.md): money is
 * integer paise, ratios 0..1 (null when the denominator is 0), durations seconds, distances km,
 * timestamps UTC RFC 3339, days IST `YYYY-MM-DD`.
 */
import { authedFetch } from "./api";

// ---- AN-011 filter set -------------------------------------------------------------------
export interface AnalyticsApiFilters {
  from: string;
  to: string;
  cluster_id?: string;
  store_id?: string;
  officer_id?: string;
  crop_id?: string;
}

export interface FiltersOut {
  from: string;
  to: string;
  cluster_id?: string | null;
  store_id?: string | null;
  officer_id?: string | null;
  crop_id?: string | null;
  days: number;
  /** Role narrowing applied by the API: tenant | cluster | store | own. */
  scope: string;
}

export interface SeriesPoint {
  start: string;
  end: string;
  value: number | null;
}

// ---- C10 owner home ----------------------------------------------------------------------
export type KpiKey =
  | "revenue"
  | "own_brand_share"
  | "credit_outstanding"
  | "credit_overdue"
  | "verified_visits"
  | "active_farmers"
  | "open_flags";
export type KpiUnit = "paise" | "ratio" | "count";

export interface KpiOut {
  key: KpiKey | string;
  unit: KpiUnit;
  value: number | null;
  target: number | null;
  last_year: number | null;
  trend: SeriesPoint[];
}

export type PerformanceBand = "green" | "amber" | "red" | "none";

export interface StoreMapItem {
  id: string;
  code: string;
  name: string;
  district: string;
  cluster_id: string | null;
  lat: number | null;
  lon: number | null;
  revenue_paise: number;
  own_brand_share: number | null;
  overdue_paise: number;
  score: number | null;
  band: PerformanceBand;
}

export interface OfficerRankOut {
  id: string;
  name: string;
  store_id: string | null;
  verified_visits: number;
  duty_days: number;
  verified_visits_per_day: number | null;
}

export interface HighSeverityFlag {
  id: string;
  rule: string;
  severity: string;
  title: string;
  opened_at: string;
  officer_id?: string | null;
  store_id?: string | null;
  farmer_id?: string | null;
}

export interface OwnerHomeOut {
  filters: FiltersOut;
  granularity: "day" | "week";
  kpis: KpiOut[];
  credit_overdue_buckets: Record<string, number>;
  series: {
    revenue: SeriesPoint[];
    revenue_last_year: SeriesPoint[];
    own_brand_share: SeriesPoint[];
  };
  stores: StoreMapItem[];
  officers_top: OfficerRankOut[];
  officers_bottom: OfficerRankOut[];
  high_severity_flags: HighSeverityFlag[];
  crop_health_alerts: Array<Record<string, unknown>>;
  notes: Record<string, string>;
}

// ---- C20 / C21 field team ----------------------------------------------------------------
export interface ScorecardRow {
  officer_id: string;
  name: string;
  store_id: string | null;
  cluster_id: string | null;
  rank: number;
  duty_days: number;
  visits: number;
  verified_visits: number;
  verified_visits_per_day: number | null;
  unique_farmers_reached: number;
  new_registrations: number;
  confirmation_rate: number | null;
  avg_time_on_farm_s: number | null;
  time_on_farm_s: number;
  km_per_day: number | null;
  conversion_rate: number | null;
  converted_farmers: number;
  visited_farmers: number;
  collections_paise: number;
  flags: number;
  trend: SeriesPoint[];
}

export interface FieldTeamOut {
  filters: FiltersOut;
  location_visible: boolean;
  items: ScorecardRow[];
}

export interface DutyDayOut {
  day: string;
  start_at: string;
  end_at: string | null;
  km: number | null;
  visits: number;
  verified_visits: number;
  time_on_farm_s: number;
}

export interface OfficerVisitOut {
  id: string;
  farmer_id: string;
  farmer_name: string;
  checkin_at: string;
  checkout_at: string | null;
  status: string;
  score: number | null;
  purpose: string;
}

export interface OfficerProfileOut {
  filters: FiltersOut;
  id: string;
  name: string;
  phone: string;
  status: string;
  store_id: string | null;
  store_name: string | null;
  cluster_id: string | null;
  on_duty: boolean;
  location_visible: boolean;
  scorecard: ScorecardRow;
  duty_days: DutyDayOut[];
  recent_visits: OfficerVisitOut[];
}

// ---- C22 day replay ----------------------------------------------------------------------
export interface ReplayPoint {
  ts: string;
  lat: number;
  lon: number;
  accuracy_m: number;
}

export interface StopOut {
  lat: number;
  lon: number;
  start: string;
  end: string;
  duration_s: number;
}

export interface GapOut {
  start: string;
  end: string;
  duration_s: number;
  duty_session_id: string;
  reason: string | null;
}

export type ProofKind = "geofence" | "photo" | "confirmation" | "duration" | "integrity";

export interface ProofItem {
  kind: ProofKind;
  satisfied: boolean;
  points: number;
  max_points: number;
}

export type VisitColour = "green" | "amber" | "red" | "grey";

export interface ReplayVisit {
  id: string;
  farmer_id: string;
  farmer_name: string;
  purpose: string;
  checkin_at: string;
  checkout_at: string | null;
  duration_s: number | null;
  lat: number;
  lon: number;
  geofence_result: string;
  status: string;
  colour: VisitColour;
  score: number | null;
  score_components: Record<string, number>;
  proof: ProofItem[];
  confirmed_at: string | null;
  photos: number;
}

export type TimelineType =
  | "duty_start"
  | "duty_end"
  | "visit_checkin"
  | "visit_checkout"
  | "stop"
  | "gap_start"
  | "gap_end";

export interface TimelineEvent {
  ts: string;
  type: TimelineType;
  ref_id?: string | null;
  detail?: Record<string, unknown>;
}

export interface DayReplayOut {
  filters: FiltersOut;
  officer_id: string;
  officer_name: string;
  date: string;
  duty_sessions: Array<{
    id: string;
    start_at: string;
    end_at: string | null;
    end_reason: string | null;
    km: number | null;
  }>;
  km: number;
  track: { type: "MultiLineString"; coordinates: number[][][] };
  points: ReplayPoint[];
  stops: StopOut[];
  gaps: GapOut[];
  visits: ReplayVisit[];
  timeline: TimelineEvent[];
}

// ---- C30 / C31 farmers -------------------------------------------------------------------
export type CreditRisk = "low" | "medium" | "high";
export const CREDIT_RISKS: readonly CreditRisk[] = ["low", "medium", "high"];
export const LAST_VISIT_WINDOWS = ["7d", "30d", "90d", "over_90d", "never"] as const;
export type LastVisitWindow = (typeof LAST_VISIT_WINDOWS)[number];
export const CROP_STAGES = [
  "sown",
  "vegetative",
  "flowering",
  "fruiting",
  "maturity",
  "harvested",
] as const;
export type CropStage = (typeof CROP_STAGES)[number];
export const FARMER_SORTS = [
  "name",
  "last_visit",
  "last_purchase",
  "ltv",
  "balance",
  "overdue",
] as const;
export type FarmerSortKey = (typeof FARMER_SORTS)[number];

export interface FarmerRow {
  id: string;
  name: string;
  phone_masked: string;
  village_id: string;
  village: string;
  district: string;
  store_id: string | null;
  registered_by: string | null;
  crops: string[];
  stages: string[];
  acres: number;
  last_visit_at: string | null;
  last_purchase_at: string | null;
  balance_paise: number;
  overdue_paise: number;
  credit_risk: CreditRisk;
  ltv_paise: number;
  app_user: boolean;
  consent_marketing: boolean;
}

export interface FarmerDirectoryOut {
  filters: FiltersOut;
  items: FarmerRow[];
  next_cursor: string | null;
  total: number;
}

export interface FarmerDirectoryQuery {
  q?: string;
  district?: string;
  stage?: string;
  credit_risk?: string;
  last_visit?: string;
  sort?: string;
  cursor?: string;
  limit?: number;
}

export interface GeoJsonPolygon {
  type: "Polygon";
  coordinates: number[][][];
}

export interface Farmer360Out {
  filters: FiltersOut;
  profile: {
    id: string;
    name: string;
    phone: string;
    phone_verified: boolean;
    language: string;
    landmark: string | null;
    source: string;
    village_id: string;
    village: string;
    district: string;
    store_id: string | null;
    registered_by: string | null;
    registered_by_name: string | null;
    created_at: string;
    updated_at: string;
  };
  farms: Array<{
    id: string;
    name: string | null;
    survey_no: string | null;
    area_acres: number;
    area_acres_computed: number | null;
    soil: string | null;
    irrigation: string | null;
    boundary: GeoJsonPolygon | null;
    centroid: { type: "Point"; coordinates: number[] } | null;
    crop_plots: Array<{
      id: string;
      crop_id: string;
      crop_code: string;
      crop_name: string;
      variety: string | null;
      season: string;
      sowing_date: string;
      stage: string | null;
      expected_harvest: string | null;
      area_acres: number | null;
    }>;
  }>;
  visits: Array<{
    id: string;
    officer_id: string;
    officer_name: string;
    purpose: string;
    checkin_at: string;
    checkout_at: string | null;
    status: string;
    score: number | null;
    confirmed: boolean;
    crop_stage: string | null;
    /** Not in the P0 payload; shown when the API adds it. */
    photos?: number;
  }>;
  diagnoses: Array<Record<string, unknown>>;
  orders: Array<{
    id: string;
    store_id: string;
    channel: string;
    status: string;
    total_paise: number;
    placed_at: string | null;
    invoice_no: string | null;
    lines: number;
  }>;
  khata: {
    balance_paise: number;
    overdue_paise: number;
    overdue_buckets: Record<string, number>;
    next_due_date: string | null;
    credit_limits: Array<{ store_id: string; limit_paise: number }>;
    last_payment_at: string | null;
    credit_risk: CreditRisk;
  };
  consent: {
    current: Record<string, boolean>;
    history: Array<{
      purpose: string;
      granted: boolean;
      at: string;
      version: string;
      channel: string;
    }>;
  };
  app_usage: {
    has_app_login: boolean;
    last_session_at: string | null;
    sessions_last_60_days: number;
    proxy: string;
  };
  ltv_paise: number;
  last_visit_at: string | null;
  last_purchase_at: string | null;
  active: boolean;
  notes: Record<string, string>;
}

// ---- C40 / C41 stores --------------------------------------------------------------------
export interface StoreRow {
  id: string;
  code: string;
  name: string;
  district: string;
  cluster_id: string | null;
  net_sales_paise: number;
  cogs_paise: number;
  gross_margin_paise: number;
  gross_margin_pct: number | null;
  own_brand_share: number | null;
  orders: number;
  stock_value_paise: number;
  credit_outstanding_paise: number;
  credit_overdue_paise: number;
  last_day_close: { business_date: string; variance_paise: number; status: string } | null;
}

export interface StoreListOut {
  filters: FiltersOut;
  items: StoreRow[];
}

export interface PnlMonth {
  month: string;
  partial: boolean;
  gross_sales_paise: number;
  discounts_paise: number;
  net_sales_paise: number;
  cogs_paise: number;
  gross_margin_paise: number;
  gross_margin_pct: number | null;
  write_offs_paise: number;
  contribution_paise: number;
}

export interface StoreDetailOut {
  filters: FiltersOut;
  id: string;
  code: string;
  name: string;
  district: string;
  cluster_id: string | null;
  net_sales_paise: number;
  cogs_paise: number;
  gross_margin_paise: number;
  gross_margin_pct: number | null;
  sales_by_category: Array<{
    category: string;
    net_sales_paise: number;
    gross_margin_paise: number;
    share: number | null;
  }>;
  brand_split: {
    own_brand_paise: number;
    multi_brand_paise: number;
    own_brand_share: number | null;
    own_brand_margin_paise: number;
    multi_brand_margin_paise: number;
  };
  stock: {
    value_paise: number;
    skus_in_stock: number;
    turns: number | null;
    turns_annualised: number | null;
    stockouts: Array<{ sku_id: string; product_name: string; pack: string }>;
  };
  credit_book: {
    outstanding_paise: number;
    overdue_paise: number;
    buckets: Record<string, number>;
    accounts: number;
  };
  day_closes: Array<{
    business_date: string;
    cash_expected_paise: number;
    cash_counted_paise: number;
    variance_paise: number;
    status: string;
    variance_flagged: boolean;
  }>;
  pnl: PnlMonth[];
  pnl_opex_included?: boolean;
  pnl_note: string;
}

/** Overdue buckets in display order (SPEC 5.2). */
export const OVERDUE_BUCKETS = ["0_30", "31_60", "61_90", "90_plus"] as const;

// ---- client ------------------------------------------------------------------------------
export function queryString(params: object): string {
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(params as Record<string, unknown>)) {
    if (v === undefined || v === null || v === "") continue;
    qs.set(k, String(v));
  }
  const s = qs.toString();
  return s ? `?${s}` : "";
}

const get = <T>(path: string, params: object = {}) =>
  authedFetch<T>(`v1/analytics/${path}${queryString(params)}`);

export const analytics = {
  ownerHome: (f: AnalyticsApiFilters) => get<OwnerHomeOut>("owner-home", f),
  fieldTeam: (f: AnalyticsApiFilters) => get<FieldTeamOut>("field-team", f),
  officer: (id: string, f: AnalyticsApiFilters) =>
    get<OfficerProfileOut>(`officers/${encodeURIComponent(id)}`, f),
  dayReplay: (id: string, date: string, f: AnalyticsApiFilters) =>
    get<DayReplayOut>(`officers/${encodeURIComponent(id)}/day-replay`, { ...f, date }),
  farmers: (f: AnalyticsApiFilters, q: FarmerDirectoryQuery) =>
    get<FarmerDirectoryOut>("farmers", { ...f, ...q }),
  farmer360: (id: string, f: AnalyticsApiFilters) =>
    get<Farmer360Out>(`farmers/${encodeURIComponent(id)}/360`, f),
  stores: (f: AnalyticsApiFilters) => get<StoreListOut>("stores", f),
  store: (id: string, f: AnalyticsApiFilters) =>
    get<StoreDetailOut>(`stores/${encodeURIComponent(id)}`, f),
};
