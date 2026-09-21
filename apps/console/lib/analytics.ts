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
  /** SPEC 5.2 farmer LTV: cumulative gross margin. */
  ltv_paise: number;
  /** Cumulative net sales to the farmer. */
  spend_paise: number;
  orders: number;
  /** AN-004: bought before, but no purchase and no visit in the churn window. */
  churn_risk: boolean;
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
  spend_paise: number;
  last_visit_at: string | null;
  last_purchase_at: string | null;
  active: boolean;
  churn_risk: ChurnRisk;
  notes: Record<string, string>;
}

/** AN-004 churn risk of one farmer, with the numbers behind the flag. */
export interface ChurnRisk {
  at_risk: boolean;
  window_days: number;
  days_since_last_purchase: number | null;
  days_since_last_visit: number | null;
  orders: number;
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
  /** AN-005: COGS over the range / stock at cost, scaled to a year. */
  stock_turns_annualised: number | null;
  /** SKUs the store has stocked whose on-hand is now zero. */
  stockouts: number;
  credit_outstanding_paise: number;
  credit_overdue_paise: number;
  credit_overdue_buckets: Record<string, number>;
  last_day_close: { business_date: string; variance_paise: number; status: string } | null;
  /** Summed day-close variance over the range. */
  day_close_variance_paise: number;
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
  /** AN-005 sales by brand, biggest first. */
  sales_by_brand: Array<{
    brand: string;
    own_brand: boolean;
    net_sales_paise: number;
    gross_margin_paise: number;
    gross_margin_pct: number | null;
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
    /** SKU-days out of stock over the range. */
    stockout_days: number;
    stockouts: Array<{
      sku_id: string;
      product_name: string;
      pack: string;
      days_out_of_stock: number;
      currently_out: boolean;
    }>;
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

// ---- C32 segments (AN-004) ---------------------------------------------------------------
/** The WC-008 segment definition — the same object a campaign is sent to. */
export interface SegmentDefinition {
  crop_ids?: string[];
  stages?: string[];
  districts?: string[];
  store_ids?: string[];
  min_acres?: number;
  max_acres?: number;
  purchase_within_days?: number;
  min_spend_paise?: number;
  no_purchase_within_days?: number;
  visited_within_days?: number;
  not_visited_within_days?: number;
  app_user?: boolean;
  app_active_within_days?: number;
  languages?: string[];
}

export interface SegmentFacet {
  key: string;
  count: number;
}

export interface SegmentPreviewOut {
  filters: FiltersOut;
  definition: SegmentDefinition;
  matched: number;
  consented: number;
  excluded_no_consent: number;
  app_users: number;
  churn_risk: number;
  churn_window_days: number;
  ltv_paise: number;
  spend_paise: number;
  by_crop: SegmentFacet[];
  by_district: SegmentFacet[];
  by_stage: SegmentFacet[];
  by_acreage_band: SegmentFacet[];
  by_spend_band: SegmentFacet[];
  by_last_visit: SegmentFacet[];
  by_consent: SegmentFacet[];
  by_app_usage: SegmentFacet[];
}

export interface SavedSegment {
  id: string;
  name: string;
  description: string | null;
  definition: SegmentDefinition;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  last_count: number | null;
  last_counted_at: string | null;
  version: number;
}

/** Acreage and spend band keys in display order (the API's own order). */
export const ACREAGE_BANDS = ["under_2", "2_5", "5_10", "over_10"] as const;
export const SPEND_BANDS = ["none", "under_5k", "5k_25k", "25k_1l", "over_1l"] as const;
export const SEGMENT_VISIT_WINDOWS = ["7d", "30d", "90d", "over_90d", "never"] as const;

export interface ChurnRow {
  id: string;
  name: string;
  phone_masked: string;
  village: string;
  district: string;
  store_id: string | null;
  registered_by: string | null;
  crops: string[];
  ltv_paise: number;
  spend_paise: number;
  orders: number;
  last_purchase_at: string | null;
  last_visit_at: string | null;
  days_since_last_purchase: number | null;
  days_since_last_visit: number | null;
  balance_paise: number;
  overdue_paise: number;
  credit_risk: CreditRisk;
  app_user: boolean;
  consent_marketing: boolean;
}

export interface ChurnListOut {
  filters: FiltersOut;
  window_days: number;
  total: number;
  items: ChurnRow[];
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
  churnRisk: (f: AnalyticsApiFilters, q: { days?: number; limit?: number } = {}) =>
    get<ChurnListOut>("farmers-churn-risk", { ...f, ...q }),
  segmentPreview: (f: AnalyticsApiFilters, definition: SegmentDefinition) =>
    authedFetch<SegmentPreviewOut>(`v1/analytics/segments/preview${queryString(f)}`, {
      body: { definition },
    }),
  savedSegments: () => authedFetch<{ items: SavedSegment[] }>("v1/analytics/segments"),
  savedSegment: (id: string) =>
    authedFetch<SavedSegment>(`v1/analytics/segments/${encodeURIComponent(id)}`),
  createSegment: (
    f: AnalyticsApiFilters,
    body: { name: string; description: string | null; definition: SegmentDefinition },
  ) => authedFetch<SavedSegment>(`v1/analytics/segments${queryString(f)}`, { body }),
  updateSegment: (
    id: string,
    f: AnalyticsApiFilters,
    body: { name?: string; description?: string | null; definition?: SegmentDefinition },
  ) =>
    authedFetch<SavedSegment>(`v1/analytics/segments/${encodeURIComponent(id)}${queryString(f)}`, {
      body,
      method: "PATCH",
    }),
  deleteSegment: (id: string) =>
    authedFetch<void>(`v1/analytics/segments/${encodeURIComponent(id)}`, { method: "DELETE" }),
  /** AN-016: a question in words; the answer, the rows and the generated read-only SQL. */
  ask: (question: string) => authedFetch<AskOut>("v1/analytics/ask", { body: { question } }),
  askViews: () => authedFetch<AskViewsOut>("v1/analytics/ask/views"),
  /** FM-013: referrals per store, and the flat list. */
  referralSummary: () => authedFetch<ReferralSummaryOut>("v1/referrals/summary"),
  referrals: (q: { store_id?: string; status?: ReferralStatus; limit?: number } = {}) =>
    authedFetch<ReferralListOut>(`v1/referrals${queryString(q)}`),
  rewardReferral: (id: string) =>
    authedFetch<ReferralRow>(`v1/referrals/${encodeURIComponent(id)}/reward`, { body: {} }),
};

// ---- AN-016 natural-language questions ----------------------------------------------------
/** `POST /v1/analytics/ask`. `sql` is generated and read-only; it is shown, never re-sent. */
export interface AskOut {
  answered: boolean;
  question: string;
  answer: string | null;
  reason: string | null;
  message_key: string | null;
  sql: string | null;
  views: string[];
  columns: string[];
  rows: Record<string, unknown>[];
  row_count: number;
  truncated: boolean;
  scope: string;
  model: string | null;
  elapsed_ms: number;
}

export interface AskViewOut {
  name: string;
  grain: string;
  description: string;
  columns: { name: string; description: string }[];
}

export interface AskViewsOut {
  views: AskViewOut[];
  enabled: boolean;
}

// ---- FM-013 referrals ---------------------------------------------------------------------
export type ReferralStatus = "pending" | "attributed" | "rewarded" | "rejected";

export interface ReferralRow {
  id: string;
  code: string;
  status: ReferralStatus;
  source: string;
  referrer_farmer_id: string;
  invited_farmer_id: string | null;
  /** Last four digits only (AN-014 / SEC-026): the console never sees a number. */
  invited_phone_last4: string | null;
  store_id: string | null;
  referrer_reward_paise: number;
  store_reward_paise: number;
  reward_note: string | null;
  attributed_at: string | null;
  rewarded_at: string | null;
  created_at: string;
}

export interface ReferralListOut {
  items: ReferralRow[];
  total: number;
}

export interface StoreReferralsRow {
  store_id: string | null;
  store_code: string | null;
  store_name: string | null;
  pending: number;
  attributed: number;
  rewarded: number;
  total: number;
  referrer_reward_paise: number;
  store_reward_paise: number;
}

export interface ReferralSummaryOut {
  stores: StoreReferralsRow[];
  pending: number;
  attributed: number;
  rewarded: number;
}
