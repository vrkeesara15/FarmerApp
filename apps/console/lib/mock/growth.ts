/**
 * In-memory campaigns, targets and incentives, travel claims and exports for the mock API
 * (WC-008, WC-009, WC-013, AN-008), so C80-C82, C90, C91 and C100 run and Playwright passes
 * without apps/api. Mirrors the contracts in docs/prs/M7-growth-api.md:
 *
 * - every audience is consent-filtered (a fixed slice of the seeded farmers has no marketing
 *   consent and is only ever reported as `excluded_no_consent`);
 * - scheduling freezes the audience and a deterministic holdout split;
 * - the incentive engine mirrors `farmerapp/incentives/rules.py` (components -> multipliers ->
 *   total cap -> clawback), so the C90 preview reacts to an edited rule document;
 * - `POST /exports` and writing a schedule answer 401 `step_up_required` without a token.
 *
 * Holds no real data.
 */
import type { MockActor, MockResult } from "./catalog";
import { mockStepUpOk, recordAudit } from "./admin";
import { MOCK_FARMERS, MOCK_OFFICERS, MOCK_STORES } from "./analytics";

type Json = Record<string, unknown>;

const OK_WRITE = ["owner", "director", "tenant_admin"];
const CAMPAIGN_READ = [...OK_WRITE, "auditor"];
const TARGET_READ = [...OK_WRITE, "auditor", "accountant", "cluster_head", "store_manager"];
const CLAIM_DECIDE = ["cluster_head", "owner", "director", "tenant_admin"];
const CLAIM_READ = [...CLAIM_DECIDE, "auditor", "accountant", "field_officer"];
const SCHEDULE_ROLES = [...TARGET_READ];
const EXPORT_ROLES = [...TARGET_READ, "field_officer", "agronomist"];

function problem(status: number, code: string, detail?: string, extra?: Json): MockResult {
  return {
    status,
    json: {
      type: `https://farmerapp.dev/problems/${code}`,
      title: code,
      status,
      code,
      detail,
      ...extra,
    },
    headers: { "content-type": "application/problem+json" },
  };
}
const ok = (json: unknown, status = 200): MockResult => ({ status, json });
const stepUpRequired = () =>
  problem(401, "step_up_required", "This action needs a fresh one-time code.", {
    step_up_url: "/v1/auth/step-up/send",
  });

/** Deterministic 0..1 from a string (the same trick lib/mock/analytics.ts uses). */
function rnd(seed: string): number {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 100000) / 100000;
}

const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
const D = 86_400_000;

/** A fifth of the farmers never granted marketing consent; they are never selectable. */
const hasConsent = (farmerId: string) => rnd(`${farmerId}:consent`) > 0.2;
const languageOf = (farmerId: string) =>
  (["te", "hi", "kn", "mr", "en"] as const)[Math.floor(rnd(`${farmerId}:lang`) * 5)]!;

// ---- campaigns ------------------------------------------------------------------------------

interface Segment {
  crop_ids?: string[];
  stages?: string[];
  districts?: string[];
  store_ids?: string[];
  purchase_within_days?: number;
  min_spend_paise?: number;
  no_purchase_within_days?: number;
  visited_within_days?: number;
  not_visited_within_days?: number;
  app_user?: boolean;
  app_active_within_days?: number;
  languages?: string[];
}

interface Recipient {
  farmer_id: string;
  farmer_name: string;
  phone_masked: string;
  arm: "target" | "holdout";
  language: string;
  status: string;
  skip_reason: string | null;
  dlt_template_id: string | null;
  sent_at: string | null;
  delivered_at: string | null;
  opened_at: string | null;
  error: string | null;
}

interface Campaign {
  id: string;
  name: string;
  channel: string;
  status: string;
  segment: Segment;
  messages: Record<string, string>;
  template_key: string | null;
  attribution_days: number;
  holdout_pct: number;
  notes: string | null;
  audience: number | null;
  send_at: string | null;
  created_at: string;
  updated_at: string;
  recipients: Recipient[];
}

/** Farmers matching a segment, before the consent filter. */
function matches(segment: Segment): typeof MOCK_FARMERS {
  return MOCK_FARMERS.filter((f) => {
    if (segment.crop_ids?.length && !f.crop_ids.some((c) => segment.crop_ids!.includes(c)))
      return false;
    if (segment.stages?.length && !segment.stages.includes(f.stage)) return false;
    if (
      segment.districts?.length &&
      !segment.districts.some((d) => d.toLowerCase() === f.district.toLowerCase())
    )
      return false;
    if (segment.store_ids?.length && !segment.store_ids.includes(f.store_id)) return false;
    if (segment.languages?.length && !segment.languages.includes(languageOf(f.id))) return false;
    if (segment.app_user === true && rnd(`${f.id}:app`) < 0.4) return false;
    if (segment.app_user === false && rnd(`${f.id}:app`) >= 0.4) return false;
    if (segment.purchase_within_days !== undefined && rnd(`${f.id}:buy`) > 0.7) return false;
    if (segment.no_purchase_within_days !== undefined && rnd(`${f.id}:buy`) <= 0.7) return false;
    if (segment.visited_within_days !== undefined && rnd(`${f.id}:visit`) > 0.65) return false;
    if (segment.not_visited_within_days !== undefined && rnd(`${f.id}:visit`) <= 0.65) return false;
    if (segment.app_active_within_days !== undefined && rnd(`${f.id}:active`) > 0.5) return false;
    if (segment.min_spend_paise !== undefined && rnd(`${f.id}:spend`) < 0.35) return false;
    return true;
  });
}

function segmentCount(segment: Segment): { count: number; excluded_no_consent: number } {
  const all = matches(segment);
  const consented = all.filter((f) => hasConsent(f.id));
  return { count: consented.length, excluded_no_consent: all.length - consented.length };
}

const mask = (phone: string) => `+91******${phone.slice(-4)}`;

function freezeAudience(c: Campaign): void {
  const consented = matches(c.segment).filter((f) => hasConsent(f.id));
  const holdoutCount = Math.floor((consented.length * c.holdout_pct) / 100);
  // Deterministic split: the lowest hashes go to the holdout arm.
  const ranked = [...consented].sort((a, b) => rnd(`${a.id}:arm`) - rnd(`${b.id}:arm`));
  c.recipients = ranked.map((f, i) => ({
    farmer_id: f.id,
    farmer_name: f.name,
    phone_masked: mask(f.phone),
    arm: i < holdoutCount ? "holdout" : "target",
    language: languageOf(f.id),
    status: i < holdoutCount ? "holdout" : "pending",
    skip_reason: null,
    dlt_template_id: c.channel === "sms" ? "DLT-1107161234567" : null,
    sent_at: null,
    delivered_at: null,
    opened_at: null,
    error: null,
  }));
  c.audience = consented.length;
}

/** The mock "send job": turns a scheduled campaign's pending rows into sent / delivered. */
function deliver(c: Campaign): void {
  for (const r of c.recipients) {
    if (r.status !== "pending") continue;
    const roll = rnd(`${c.id}:${r.farmer_id}:send`);
    if (roll < 0.04) {
      r.status = "skipped";
      r.skip_reason = "consent_withdrawn";
      continue;
    }
    r.status = roll < 0.12 ? "failed" : "delivered";
    r.sent_at = iso(-2 * D);
    if (r.status === "delivered") r.delivered_at = iso(-2 * D + 60_000);
    else r.error = "undeliverable";
    if (c.channel === "push" && r.status === "delivered" && roll > 0.5) r.opened_at = iso(-1 * D);
  }
  c.status = "sent";
}

function roiOf(c: Campaign): Json {
  const target = c.recipients.filter((r) => r.arm === "target");
  const holdout = c.recipients.filter((r) => r.arm === "holdout");
  const reached = target.filter((r) => r.status === "delivered" || r.status === "sent");
  const convert = (rows: Recipient[], seed: string) => {
    const buyers = rows.filter(
      (r) => rnd(`${c.id}:${r.farmer_id}:${seed}`) < (seed === "t" ? 0.18 : 0.11),
    );
    const revenue = buyers.reduce(
      (sum, r) => sum + Math.round(80_000 + rnd(`${c.id}:${r.farmer_id}:rev`) * 400_000) * 100,
      0,
    );
    const ownBrand = buyers.reduce(
      (sum, r) =>
        sum +
        Math.round(
          (80_000 + rnd(`${c.id}:${r.farmer_id}:rev`) * 400_000) *
            (seed === "t" ? 0.42 : 0.3) *
            100,
        ),
      0,
    );
    return {
      buyers: buyers.length,
      orders: buyers.length + Math.round(buyers.length * 0.2),
      revenue,
      ownBrand,
    };
  };
  const t = convert(reached, "t");
  const h = convert(holdout, "h");
  const tRate = reached.length ? t.buyers / reached.length : null;
  const hRate = holdout.length ? h.buyers / holdout.length : null;
  const tShare = t.revenue ? t.ownBrand / t.revenue : null;
  const hShare = h.revenue ? h.ownBrand / h.revenue : null;
  return {
    audience: c.audience ?? 0,
    sent: target.filter((r) => r.sent_at).length,
    delivered: target.filter((r) => r.status === "delivered").length,
    failed: target.filter((r) => r.status === "failed").length,
    skipped: target.filter((r) => r.status === "skipped").length,
    opened: c.channel === "push" ? target.filter((r) => r.opened_at).length : null,
    orders: t.orders,
    converted_farmers: t.buyers,
    conversion_rate: tRate,
    revenue_paise: t.revenue,
    own_brand_revenue_paise: t.ownBrand,
    own_brand_share: tShare,
    attribution_days: c.attribution_days,
    holdout: holdout.length
      ? {
          audience: holdout.length,
          orders: h.orders,
          converted_farmers: h.buyers,
          conversion_rate: hRate,
          revenue_paise: h.revenue,
          own_brand_revenue_paise: h.ownBrand,
          own_brand_share: hShare,
        }
      : null,
    own_brand_lift: tShare !== null && hShare !== null ? tShare - hShare : null,
    conversion_lift: tRate !== null && hRate !== null ? tRate - hRate : null,
  };
}

const publicCampaign = (c: Campaign): Json => {
  const { recipients: _recipients, ...rest } = c;
  return rest as unknown as Json;
};

// ---- incentives -------------------------------------------------------------------------------

interface RuleSet {
  id: string;
  name: string;
  version: number;
  status: string;
  definition: Json;
  activated_at: string | null;
  created_at: string;
  created_by: string | null;
}

interface Payout {
  officer_id: string;
  month: string;
  amount_paise: number;
}

const STARTER_DEFINITION: Json = {
  eligibility: { min_verified_visits: 20, count_visit_statuses: ["verified"] },
  components: [
    {
      id: "visits",
      metric: "verified_visits",
      kind: "slab_per_unit",
      slabs: [
        { from: 0, to: 40, rate_paise: 0 },
        { from: 40, rate_paise: 2000 },
      ],
    },
    { id: "sales", metric: "sales_paise", kind: "percent", rate_bp: 100, cap_paise: 500000 },
    {
      id: "own_brand",
      metric: "own_brand_share",
      kind: "threshold",
      threshold: 0.4,
      amount_paise: 100000,
    },
    { id: "farmers", metric: "new_farmers", kind: "per_unit", rate_paise: 5000 },
  ],
  multipliers: [{ metric: "attainment.sales_paise", gte: 1, factor: 1.1 }],
  cap_paise: 1500000,
  clawback: { cancelled_orders: true },
};

/** Officer metrics for a month — deterministic, so the preview is stable between renders. */
function metricsFor(officerId: string, month: string): Record<string, number> {
  const s = `${officerId}:${month}`;
  const verified = 28 + Math.floor(rnd(`${s}:v`) * 34);
  const sales = Math.round(150_000 + rnd(`${s}:s`) * 450_000) * 100;
  return {
    verified_visits: verified,
    visits: verified + Math.floor(rnd(`${s}:p`) * 8),
    new_farmers: 2 + Math.floor(rnd(`${s}:f`) * 9),
    sales_paise: sales,
    own_brand_sales_paise: Math.round(sales * (0.28 + rnd(`${s}:ob`) * 0.28)),
    own_brand_share: Math.round((0.28 + rnd(`${s}:ob`) * 0.28) * 1000) / 1000,
    collections_paise: Math.round(sales * (0.6 + rnd(`${s}:c`) * 0.35)),
    cancelled_sales_paise: Math.round(rnd(`${s}:cb`) * 60_000) * 100,
  };
}

function targetsFor(officerId: string, month: string): Record<string, number> {
  const stored = db.targets.get(`${month}|officer|${officerId}`);
  const m = metricsFor(officerId, month);
  return {
    visits_verified: stored?.visits_verified ?? 45,
    new_farmers: stored?.new_farmers ?? 6,
    sales_paise: stored?.sales_paise ?? Math.round(m.sales_paise! * 0.9),
    collections_paise: stored?.collections_paise ?? Math.round(m.collections_paise! * 0.9),
    own_brand_share_bp: stored?.own_brand_share_bp ?? 4000,
  };
}

const TARGET_METRIC_FOR: Record<string, string> = {
  verified_visits: "visits_verified",
  new_farmers: "new_farmers",
  sales_paise: "sales_paise",
  collections_paise: "collections_paise",
};

/** Mirrors farmerapp/incentives/rules.py: components -> multipliers -> cap -> clawback. */
function evaluateRules(
  definition: Json,
  metrics: Record<string, number>,
  targets: Record<string, number>,
): Json {
  const def = definition as {
    eligibility?: { min_verified_visits?: number; count_visit_statuses?: string[] };
    components?: Array<Record<string, unknown>>;
    multipliers?: Array<{ metric: string; gte: number; factor: number }>;
    cap_paise?: number | null;
    clawback?: { cancelled_orders?: boolean };
  };
  const statuses = def.eligibility?.count_visit_statuses ?? ["verified"];
  const countedVisits =
    statuses.length === 1 && statuses[0] === "verified"
      ? metrics.verified_visits!
      : metrics.visits!;
  const value = (metric: string): number =>
    metric === "verified_visits" ? countedVisits : (metrics[metric] ?? 0);

  const reasons: string[] = [];
  const min = def.eligibility?.min_verified_visits ?? 0;
  const eligible = countedVisits >= min;
  if (!eligible) reasons.push("min_verified_visits");

  const lines: Json[] = [];
  let gross = 0;
  for (const raw of def.components ?? []) {
    const c = raw as {
      id: string;
      metric: string;
      kind: string;
      rate_paise?: number;
      rate_bp?: number;
      threshold?: number;
      amount_paise?: number;
      cap_paise?: number | null;
      slabs?: Array<{
        from: number;
        to?: number | null;
        rate_paise?: number;
        amount_paise?: number;
      }>;
    };
    const v = value(c.metric);
    let amount = 0;
    switch (c.kind) {
      case "per_unit":
        amount = Math.round(v * (c.rate_paise ?? 0));
        break;
      case "percent":
        amount = Math.round((v * (c.rate_bp ?? 0)) / 10_000);
        break;
      case "threshold":
        amount = v >= (c.threshold ?? 0) ? (c.amount_paise ?? 0) : 0;
        break;
      case "slab_per_unit":
        for (const s of c.slabs ?? []) {
          const upper = s.to ?? Infinity;
          const units = Math.max(0, Math.min(v, upper) - s.from);
          amount += Math.round(units * (s.rate_paise ?? 0));
        }
        break;
      case "slab_flat": {
        const hit = (c.slabs ?? []).find((s) => v >= s.from && v < (s.to ?? Infinity));
        amount = hit?.amount_paise ?? 0;
        break;
      }
      default:
        amount = 0;
    }
    const cap = c.cap_paise ?? null;
    const capped = cap !== null && amount > cap;
    if (capped) amount = cap!;
    gross += amount;
    lines.push({
      component: c.id,
      metric: c.metric,
      value: v,
      amount_paise: eligible ? amount : 0,
      capped,
      note: null,
    });
  }
  if (!eligible) gross = 0;

  const attainment: Record<string, number> = {};
  for (const [metric, targetKey] of Object.entries(TARGET_METRIC_FOR)) {
    const target = targets[targetKey];
    if (target) attainment[metric] = value(metric) / target;
  }
  for (const m of def.multipliers ?? []) {
    const key = m.metric.startsWith("attainment.") ? m.metric.slice("attainment.".length) : null;
    const actual = key ? (attainment[key] ?? 0) : value(m.metric);
    if (actual >= m.gte) gross = Math.round(gross * m.factor);
  }
  if (def.cap_paise != null) gross = Math.min(gross, def.cap_paise);

  const salesRateBp = (def.components ?? []).find(
    (c) => (c as { kind?: string }).kind === "percent",
  ) as { rate_bp?: number } | undefined;
  const clawback =
    def.clawback?.cancelled_orders && eligible
      ? Math.round(((metrics.cancelled_sales_paise ?? 0) * (salesRateBp?.rate_bp ?? 0)) / 10_000)
      : 0;

  return {
    status: "preview",
    eligible,
    metrics: { ...metrics, verified_visits: countedVisits },
    targets,
    lines,
    gross_paise: gross,
    clawback_paise: clawback,
    amount_paise: Math.max(0, gross - clawback),
    reasons,
  };
}

function previewFor(officerId: string, month: string, definition: Json | null): Json {
  const active = db.rules.find((r) => r.status === "active") ?? null;
  const def = definition ?? active?.definition ?? null;
  const officer = MOCK_OFFICERS.find((o) => o.id === officerId);
  const base = {
    officer_id: officerId,
    officer_name: officer?.name ?? null,
    period_start: `${month}-01`,
    period_end: `${month}-01`,
    rule_set_id: definition ? null : (active?.id ?? null),
    rule_version: definition ? null : (active?.version ?? null),
  };
  if (!def)
    return {
      ...base,
      status: "preview",
      eligible: false,
      metrics: metricsFor(officerId, month),
      targets: targetsFor(officerId, month),
      lines: [],
      gross_paise: 0,
      clawback_paise: 0,
      amount_paise: 0,
      reasons: ["no_active_incentive_rules"],
    };
  const frozen = db.payouts.find((p) => p.officer_id === officerId && p.month === month);
  const result = evaluateRules(def, metricsFor(officerId, month), targetsFor(officerId, month));
  return {
    ...base,
    ...result,
    ...(frozen ? { status: "closed", amount_paise: frozen.amount_paise } : {}),
  };
}

// ---- travel ------------------------------------------------------------------------------------

interface Claim {
  id: string;
  tenant_id: string;
  officer_id: string;
  officer_name: string;
  claim_date: string;
  type: string;
  amount_paise: number;
  receipt_uri: string;
  receipt_url: string;
  note: string | null;
  km_computed: number;
  status: string;
  decided_by: string | null;
  decided_at: string | null;
  decision_note: string | null;
  created_at: string;
  updated_at: string;
  version: number;
}

/** Inline SVG so the receipt photo renders offline (the API serves a signed GCS URL). */
function receiptImage(label: string): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="240" height="320"><rect width="240" height="320" fill="#f4f1ea"/><rect x="24" y="28" width="192" height="230" fill="#fff" stroke="#c9c2b4"/><text x="120" y="80" font-family="monospace" font-size="16" text-anchor="middle" fill="#333">FUEL</text><text x="120" y="120" font-family="monospace" font-size="14" text-anchor="middle" fill="#333">${label}</text></svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

const TA_RATE = 300;
const TA_CAP_KM = 150;

function dayKm(officerId: string, date: string): number {
  return Math.round((25 + rnd(`${officerId}:${date}:km`) * 120) * 10) / 10;
}

function statementFor(officerId: string, month: string): Json {
  const [y, m] = month.split("-").map(Number) as [number, number];
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const days: Json[] = [];
  let kmTotal = 0;
  let kmCapped = 0;
  let ta = 0;
  for (let d = 1; d <= last; d++) {
    const date = `${month}-${String(d).padStart(2, "0")}`;
    if (new Date(`${date}T00:00:00Z`).getUTCDay() === 0) continue;
    const km = dayKm(officerId, date);
    const capped = Math.min(km, TA_CAP_KM);
    const paise = Math.round(capped * TA_RATE);
    kmTotal += km;
    kmCapped += capped;
    ta += paise;
    days.push({
      date,
      sessions: 1,
      km,
      km_capped: capped,
      cap_km: TA_CAP_KM,
      rate_per_km_paise: TA_RATE,
      ta_paise: paise,
      open_session: false,
    });
  }
  const claims = db.claims.filter(
    (c) => c.officer_id === officerId && c.claim_date.startsWith(month),
  );
  const sum = (status: string) =>
    claims.filter((c) => c.status === status).reduce((a, c) => a + c.amount_paise, 0);
  const approved = sum("approved");
  return {
    officer_id: officerId,
    officer_name: MOCK_OFFICERS.find((o) => o.id === officerId)?.name ?? null,
    month,
    rate_per_km_paise: TA_RATE,
    cap_km: TA_CAP_KM,
    days,
    km_total: Math.round(kmTotal * 10) / 10,
    km_capped_total: Math.round(kmCapped * 10) / 10,
    ta_total_paise: ta,
    claims,
    claims_submitted_paise: sum("submitted"),
    claims_approved_paise: approved,
    claims_rejected_paise: sum("rejected"),
    payable_paise: ta + approved,
  };
}

// ---- exports ------------------------------------------------------------------------------------

interface ExportJob {
  id: string;
  resource: string;
  format: string;
  filters: Json;
  status: string;
  rows: number;
  size_bytes: number;
  filename: string;
  url: string;
  url_expires_at: string;
  created_at: string;
  created_by: string;
}

interface Schedule {
  id: string;
  name: string;
  resource: string;
  format: string;
  filters: Json;
  recipients: string[];
  cron: string;
  active: boolean;
  last_run_at: string | null;
  next_run_at: string | null;
  created_at: string;
}

const EXPORT_RESOURCES = [
  {
    name: "farmers",
    formats: ["csv", "xlsx"],
    columns: ["name", "village", "district", "crops", "last_visit", "balance_paise"],
    filters: ["crop", "district", "stage", "store_id"],
    description: "Farmer directory in your scope (phone masked for agronomists).",
  },
  {
    name: "orders",
    formats: ["csv", "xlsx"],
    columns: ["order_no", "store", "farmer", "net_paise", "status", "placed_at"],
    filters: ["from", "to", "store_id", "status"],
    description: "Orders with line totals and own-brand share.",
  },
  {
    name: "payments",
    formats: ["csv", "xlsx"],
    columns: ["receipt_no", "store", "farmer", "amount_paise", "mode", "received_at"],
    filters: ["from", "to", "store_id"],
    description: "Receipts and khata settlements.",
  },
  {
    name: "visits",
    formats: ["csv", "xlsx"],
    columns: ["officer", "farmer", "status", "score", "started_at", "duration_s"],
    filters: ["from", "to", "officer_id", "store_id"],
    description: "Visits with the VV-003 verification outcome.",
  },
  {
    name: "flags",
    formats: ["csv", "xlsx"],
    columns: ["rule_id", "severity", "subject", "status", "created_at", "resolved_at"],
    filters: ["status", "severity", "rule_id"],
    description: "Validation flags and their resolution.",
  },
  {
    name: "stock",
    formats: ["csv", "xlsx"],
    columns: ["store", "sku", "on_hand", "batch_no", "expiry"],
    filters: ["store_id"],
    description: "Stock on hand per store and batch.",
  },
  {
    name: "audit_logs",
    formats: ["csv"],
    columns: ["created_at", "actor", "action", "entity", "entity_id"],
    filters: ["from", "to", "action"],
    description: "Audit trail (owner, director, tenant admin, auditor).",
  },
  {
    name: "consent_records",
    formats: ["csv"],
    columns: ["farmer", "purpose", "granted", "recorded_at", "source"],
    filters: ["purpose"],
    description: "Consent records (NF-013).",
  },
];

const RESOURCE_ROLES: Record<string, readonly string[]> = {
  audit_logs: ["owner", "director", "tenant_admin", "auditor"],
  consent_records: ["owner", "director", "tenant_admin", "auditor"],
};

// ---- store -------------------------------------------------------------------------------------

interface Db {
  campaigns: Campaign[];
  rules: RuleSet[];
  targets: Map<string, Record<string, number>>;
  payouts: Payout[];
  claims: Claim[];
  exports: ExportJob[];
  schedules: Schedule[];
  seq: number;
}

function seed(): Db {
  const segment: Segment = { crop_ids: ["crop-cotton"], districts: ["Warangal", "Karimnagar"] };
  const sent: Campaign = {
    id: "camp-0001",
    name: "Cotton pink bollworm advisory",
    channel: "sms",
    status: "scheduled",
    segment,
    messages: {
      en: "Scout your cotton for pink bollworm this week. Visit FCC {store} for advice.",
      te: "ఈ వారం మీ పత్తిలో గులాబీ కాయతొలుచు పురుగును పరిశీలించండి.",
    },
    template_key: "advisory_v1",
    attribution_days: 14,
    holdout_pct: 10,
    notes: null,
    audience: null,
    send_at: iso(-3 * D),
    created_at: iso(-10 * D),
    updated_at: iso(-3 * D),
    recipients: [],
  };
  freezeAudience(sent);
  deliver(sent);

  const draft: Campaign = {
    id: "camp-0002",
    name: "Paddy top-dressing reminder",
    channel: "whatsapp",
    status: "draft",
    segment: { crop_ids: ["crop-paddy"], stages: ["vegetative"] },
    messages: { en: "Time for the first top dressing on your paddy." },
    template_key: null,
    attribution_days: 14,
    holdout_pct: 0,
    notes: null,
    audience: null,
    send_at: null,
    created_at: iso(-2 * D),
    updated_at: iso(-2 * D),
    recipients: [],
  };

  const rules: RuleSet[] = [
    {
      id: "rules-0001",
      name: "Field incentive 2026",
      version: 1,
      status: "active",
      definition: STARTER_DEFINITION,
      activated_at: iso(-60 * D),
      created_at: iso(-60 * D),
      created_by: "u-owner",
    },
  ];

  const month = (() => {
    const d = new Date();
    d.setUTCMonth(d.getUTCMonth() - 1);
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
  })();
  const claims: Claim[] = MOCK_OFFICERS.slice(0, 4).map((o, i) => {
    const date = `${month}-${String(4 + i * 5).padStart(2, "0")}`;
    return {
      id: `claim-${String(i + 1).padStart(4, "0")}`,
      tenant_id: "t1",
      officer_id: o.id,
      officer_name: o.name,
      claim_date: date,
      type: (["fuel", "bus", "fuel", "other"] as const)[i]!,
      amount_paise: [48000, 12000, 63000, 25000][i]!,
      receipt_uri: `gs://farmerapp-dev-media/travel/${o.id}-${date}.jpg`,
      receipt_url: receiptImage(date),
      note: i === 2 ? "Long day, two clusters." : null,
      km_computed: dayKm(o.id, date),
      status: "submitted",
      decided_by: null,
      decided_at: null,
      decision_note: null,
      created_at: iso(-(20 - i) * D),
      updated_at: iso(-(20 - i) * D),
      version: 1,
    };
  });

  return {
    campaigns: [draft, sent],
    rules,
    targets: new Map(),
    payouts: [],
    claims,
    exports: [
      {
        id: "exp-0001",
        resource: "orders",
        format: "csv",
        filters: { from: "2026-08-01", to: "2026-08-31" },
        status: "ready",
        rows: 1842,
        size_bytes: 214_880,
        filename: "orders-2026-08.csv",
        url: "data:text/csv;charset=utf-8,order_no%2Cstore%2Cnet_paise%0A",
        url_expires_at: iso(15 * 60_000),
        created_at: iso(-4 * D),
        created_by: "u-owner",
      },
    ],
    schedules: [
      {
        id: "sched-0001",
        name: "Weekly orders to accounts",
        resource: "orders",
        format: "csv",
        filters: {},
        recipients: ["accounts@example.com"],
        cron: "0 8 * * 1",
        active: true,
        last_run_at: iso(-3 * D),
        next_run_at: iso(4 * D),
        created_at: iso(-30 * D),
      },
    ],
    seq: 2,
  };
}

let db: Db = seed();

export function resetMockGrowth(): void {
  db = seed();
}

// ---- router --------------------------------------------------------------------------------------

/** Handles the WC-008 / WC-009 / WC-013 routes; null when the path is not one of them. */
export function handleGrowth(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor | null,
  headers: Headers,
): MockResult | null {
  const [a, b, c] = path;
  const mine = [
    "campaigns",
    "targets",
    "incentive-rules",
    "incentives",
    "travel",
    "exports",
    "report-schedules",
  ];
  if (!a || !mine.includes(a)) return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  const role = actor.role;
  const allow = (roles: readonly string[]) => roles.includes(role);
  const denied = () => problem(403, "forbidden", "Your role cannot do this.");

  if (a === "campaigns") return campaigns(method, b, c, query, body, allow, denied);
  if (a === "targets") return targets(method, query, body, allow, denied);
  if (a === "incentive-rules") return rules(method, b, c, body, actor, allow, denied);
  if (a === "incentives") return incentives(method, b, query, body, actor, headers, allow, denied);
  if (a === "travel") return travel(method, b, c, query, allow, denied);
  if (a === "exports") return exportsRoute(method, b, body, actor, headers, allow, denied);
  return schedules(method, b, body, actor, headers, allow, denied);
}

type Allow = (roles: readonly string[]) => boolean;
type Denied = () => MockResult;

function campaigns(
  method: string,
  b: string | undefined,
  c: string | undefined,
  query: URLSearchParams,
  body: Json,
  allow: Allow,
  denied: Denied,
): MockResult {
  if (method === "POST" && b === "segment-count") {
    if (!allow(CAMPAIGN_READ)) return denied();
    return ok(segmentCount((body.segment ?? {}) as Segment));
  }
  if (method === "GET" && !b) {
    if (!allow(CAMPAIGN_READ)) return denied();
    const status = query.get("status");
    const items = db.campaigns
      .filter((x) => !status || x.status === status)
      .sort((x, y) => y.created_at.localeCompare(x.created_at))
      .map(publicCampaign);
    return ok({ items, next_cursor: null });
  }
  if (method === "POST" && !b) {
    if (!allow(OK_WRITE)) return denied();
    db.seq += 1;
    const created: Campaign = {
      id: `camp-${String(db.seq).padStart(4, "0")}`,
      name: String(body.name ?? ""),
      channel: String(body.channel ?? "sms"),
      status: "draft",
      segment: (body.segment ?? {}) as Segment,
      messages: (body.messages ?? {}) as Record<string, string>,
      template_key: (body.template_key as string) ?? null,
      attribution_days: Number(body.attribution_days ?? 14),
      holdout_pct: Number(body.holdout_pct ?? 0),
      notes: (body.notes as string) ?? null,
      audience: null,
      send_at: null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      recipients: [],
    };
    db.campaigns.unshift(created);
    return ok(publicCampaign(created), 201);
  }
  const campaign = db.campaigns.find((x) => x.id === b);
  if (!campaign) return problem(404, "not_found", "Campaign not found.");
  if (method === "GET" && !c) {
    if (!allow(CAMPAIGN_READ)) return denied();
    return ok(publicCampaign(campaign));
  }
  if (method === "GET" && c === "recipients") {
    if (!allow(CAMPAIGN_READ)) return denied();
    const status = query.get("status");
    const counts: Record<string, number> = {};
    for (const r of campaign.recipients) counts[r.status] = (counts[r.status] ?? 0) + 1;
    return ok({
      items: campaign.recipients.filter((r) => !status || r.status === status).slice(0, 50),
      next_cursor: null,
      counts,
    });
  }
  if (method === "GET" && c === "roi") {
    if (!allow(CAMPAIGN_READ)) return denied();
    if (campaign.status === "draft")
      return problem(409, "invalid_campaign_state", "Schedule the campaign first.");
    return ok(roiOf(campaign));
  }
  if (method === "PATCH" && !c) {
    if (!allow(OK_WRITE)) return denied();
    if (campaign.status !== "draft")
      return problem(409, "invalid_campaign_state", "Only a draft can be edited.");
    Object.assign(campaign, {
      name: body.name !== undefined ? String(body.name) : campaign.name,
      channel: body.channel !== undefined ? String(body.channel) : campaign.channel,
      segment: (body.segment ?? campaign.segment) as Segment,
      messages: (body.messages ?? campaign.messages) as Record<string, string>,
      holdout_pct: body.holdout_pct !== undefined ? Number(body.holdout_pct) : campaign.holdout_pct,
      attribution_days:
        body.attribution_days !== undefined
          ? Number(body.attribution_days)
          : campaign.attribution_days,
      updated_at: new Date().toISOString(),
    });
    return ok(publicCampaign(campaign));
  }
  if (method === "POST" && c === "schedule") {
    if (!allow(OK_WRITE)) return denied();
    if (campaign.status !== "draft")
      return problem(409, "invalid_campaign_state", "Already scheduled.");
    const count = segmentCount(campaign.segment);
    if (count.count === 0)
      return problem(422, "empty_segment", "No farmer with marketing consent matches.");
    freezeAudience(campaign);
    campaign.status = "scheduled";
    campaign.send_at = (body.send_at as string) ?? iso(60_000);
    campaign.updated_at = new Date().toISOString();
    // The mock "send-campaigns" job runs immediately so C82 has results to show.
    deliver(campaign);
    return ok(publicCampaign(campaign));
  }
  if (method === "POST" && c === "cancel") {
    if (!allow(OK_WRITE)) return denied();
    if (!["draft", "scheduled"].includes(campaign.status))
      return problem(409, "invalid_campaign_state", "Too late to cancel.");
    campaign.status = "cancelled";
    for (const r of campaign.recipients)
      if (r.status === "pending") {
        r.status = "skipped";
        r.skip_reason = "campaign_cancelled";
      }
    return ok(publicCampaign(campaign));
  }
  return problem(405, "method_not_allowed", "Unsupported campaign call.");
}

function targetRows(month: string): Json[] {
  const rows: Json[] = [];
  for (const o of MOCK_OFFICERS.slice(0, 12)) {
    const stored = db.targets.get(`${month}|officer|${o.id}`) ?? {};
    rows.push({
      subject_type: "officer",
      subject_id: o.id,
      subject_name: o.name,
      visits_verified: stored.visits_verified ?? 45,
      new_farmers: stored.new_farmers ?? 6,
      sales_paise: stored.sales_paise ?? 40_000_000,
      collections_paise: stored.collections_paise ?? 30_000_000,
      own_brand_share_bp: stored.own_brand_share_bp ?? 4000,
    });
  }
  for (const s of MOCK_STORES.slice(0, 8)) {
    const stored = db.targets.get(`${month}|store|${s.id}`) ?? {};
    rows.push({
      subject_type: "store",
      subject_id: s.id,
      subject_name: s.name,
      visits_verified: stored.visits_verified ?? null,
      new_farmers: stored.new_farmers ?? null,
      sales_paise: stored.sales_paise ?? 250_000_000,
      collections_paise: stored.collections_paise ?? 200_000_000,
      own_brand_share_bp: stored.own_brand_share_bp ?? 3800,
    });
  }
  return rows;
}

function targets(
  method: string,
  query: URLSearchParams,
  body: Json,
  allow: Allow,
  denied: Denied,
): MockResult {
  if (method === "GET") {
    if (!allow([...TARGET_READ, "field_officer"])) return denied();
    const month = query.get("month") ?? "";
    const subject = query.get("subject_type");
    const items = targetRows(month).filter((r) => !subject || r.subject_type === subject);
    return ok({ month, items });
  }
  if (method === "PUT") {
    if (!allow([...OK_WRITE, "cluster_head"])) return denied();
    const month = String(body.month ?? "");
    for (const raw of (body.items ?? []) as Json[]) {
      const key = `${month}|${String(raw.subject_type)}|${String(raw.subject_id)}`;
      const current = db.targets.get(key) ?? {};
      for (const m of [
        "visits_verified",
        "new_farmers",
        "sales_paise",
        "collections_paise",
        "own_brand_share_bp",
      ] as const)
        if (raw[m] !== undefined && raw[m] !== null) current[m] = Number(raw[m]);
      db.targets.set(key, current);
    }
    return ok({ month, items: targetRows(month) });
  }
  return problem(405, "method_not_allowed", "Unsupported targets call.");
}

function rules(
  method: string,
  b: string | undefined,
  c: string | undefined,
  body: Json,
  actor: MockActor,
  allow: Allow,
  denied: Denied,
): MockResult {
  if (method === "GET" && !b) {
    if (!allow(TARGET_READ)) return denied();
    return ok({ items: [...db.rules].sort((x, y) => y.version - x.version) });
  }
  if (method === "GET" && b) {
    const found = db.rules.find((r) => r.id === b);
    return found ? ok(found) : problem(404, "not_found", "Rule set not found.");
  }
  if (method === "POST" && !b) {
    if (!allow(OK_WRITE)) return denied();
    const definition = (body.definition ?? {}) as Json;
    const components = (definition.components ?? []) as unknown[];
    if (!Array.isArray(components) || components.length === 0)
      return problem(422, "invalid_incentive_rules", "At least one component is required.", {
        errors: [{ loc: ["body", "definition", "components"], msg: "required" }],
      });
    db.seq += 1;
    const version = Math.max(0, ...db.rules.map((r) => r.version)) + 1;
    const created: RuleSet = {
      id: `rules-${String(db.seq).padStart(4, "0")}`,
      name: String(body.name ?? `Version ${version}`),
      version,
      status: body.activate ? "active" : "draft",
      definition,
      activated_at: body.activate ? new Date().toISOString() : null,
      created_at: new Date().toISOString(),
      created_by: actor.id,
    };
    if (body.activate) for (const r of db.rules) if (r.status === "active") r.status = "retired";
    db.rules.unshift(created);
    recordAudit(actor, "incentive_rules.create", "incentive_rule_set", created.id, null, {
      version,
    });
    return ok(created, 201);
  }
  if (method === "POST" && b && c === "activate") {
    if (!allow(OK_WRITE)) return denied();
    const found = db.rules.find((r) => r.id === b);
    if (!found) return problem(404, "not_found", "Rule set not found.");
    for (const r of db.rules) if (r.status === "active") r.status = "retired";
    found.status = "active";
    found.activated_at = new Date().toISOString();
    recordAudit(actor, "incentive_rules.activate", "incentive_rule_set", found.id, null, null);
    return ok(found);
  }
  return problem(405, "method_not_allowed", "Unsupported rules call.");
}

function incentives(
  method: string,
  b: string | undefined,
  query: URLSearchParams,
  body: Json,
  actor: MockActor,
  headers: Headers,
  allow: Allow,
  denied: Denied,
): MockResult {
  if (b === "preview" && method === "GET") {
    if (!allow([...TARGET_READ, "field_officer"])) return denied();
    const month = query.get("month") ?? "";
    const officer = query.get("officer_id") ?? MOCK_OFFICERS[0]!.id;
    const ruleSetId = query.get("rule_set_id");
    const def = ruleSetId ? (db.rules.find((r) => r.id === ruleSetId)?.definition ?? null) : null;
    return ok(previewFor(officer, month, def));
  }
  if (b === "preview" && method === "POST") {
    if (!allow(OK_WRITE)) return denied();
    return ok(
      previewFor(
        String(body.officer_id ?? MOCK_OFFICERS[0]!.id),
        String(body.month ?? ""),
        (body.definition ?? {}) as Json,
      ),
    );
  }
  if (b === "payouts" && method === "GET") {
    if (!allow(TARGET_READ)) return denied();
    const month = query.get("month") ?? "";
    const items = db.payouts
      .filter((p) => p.month === month)
      .map((p) => ({
        ...previewFor(p.officer_id, month, null),
        status: "closed",
        amount_paise: p.amount_paise,
      }));
    return ok({
      month,
      items,
      total_paise: items.reduce((a, i) => a + (i.amount_paise as number), 0),
    });
  }
  if (b === "close" && method === "POST") {
    if (!allow(["owner", "director"])) return denied();
    if (!mockStepUpOk(headers, actor)) return stepUpRequired();
    const month = String(body.month ?? "");
    if (!db.rules.some((r) => r.status === "active"))
      return problem(409, "no_active_incentive_rules", "Activate a rule version first.");
    const now = new Date();
    const currentMonth = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
    if (month >= currentMonth)
      return problem(409, "incentive_month_open", "Only an ended month can be closed.");
    db.payouts = db.payouts.filter((p) => p.month !== month);
    for (const o of MOCK_OFFICERS.slice(0, 12)) {
      const preview = previewFor(o.id, month, null);
      db.payouts.push({
        officer_id: o.id,
        month,
        amount_paise: preview.amount_paise as number,
      });
    }
    recordAudit(actor, "incentives.close", "incentive_payout", month, null, { month });
    const items = db.payouts.filter((p) => p.month === month);
    return ok({
      month,
      items: items.map((p) => ({ ...previewFor(p.officer_id, month, null), status: "closed" })),
      total_paise: items.reduce((a, p) => a + p.amount_paise, 0),
    });
  }
  return problem(404, "not_found", "Unknown incentives route.");
}

function travel(
  method: string,
  b: string | undefined,
  c: string | undefined,
  query: URLSearchParams,
  allow: Allow,
  denied: Denied,
): MockResult {
  if (b === "statement" && method === "GET") {
    if (!allow(CLAIM_READ)) return denied();
    const officer = query.get("officer_id");
    if (!officer) return problem(422, "officer_required", "officer_id is required for your role.");
    return ok(statementFor(officer, query.get("month") ?? ""));
  }
  if (b !== "claims") return problem(404, "not_found", "Unknown travel route.");
  if (method === "GET" && !c) {
    if (!allow(CLAIM_READ)) return denied();
    const status = query.get("status");
    const officer = query.get("officer_id");
    const items = db.claims
      .filter((x) => (!status || x.status === status) && (!officer || x.officer_id === officer))
      .sort((x, y) => y.claim_date.localeCompare(x.claim_date));
    return ok({ items, next_cursor: null });
  }
  const claim = db.claims.find((x) => x.id === c);
  if (!claim) return problem(404, "not_found", "Claim not found.");
  if (method === "GET") {
    if (!allow(CLAIM_READ)) return denied();
    return ok(claim);
  }
  return problem(405, "method_not_allowed", "Unsupported travel call.");
}

function decideClaim(
  id: string,
  decision: "approve" | "reject",
  body: Json,
  actor: MockActor,
): MockResult {
  const claim = db.claims.find((x) => x.id === id);
  if (!claim) return problem(404, "not_found", "Claim not found.");
  if (!CLAIM_DECIDE.includes(actor.role)) return problem(403, "forbidden", "Cluster head only.");
  if (claim.status !== "submitted")
    return problem(409, "claim_not_pending", "This claim was already decided.");
  claim.status = decision === "approve" ? "approved" : "rejected";
  claim.decided_by = actor.id;
  claim.decided_at = new Date().toISOString();
  claim.decision_note = (body.note as string) ?? null;
  claim.version += 1;
  recordAudit(actor, `travel_claim.${decision}`, "travel_claim", claim.id, null, {
    status: claim.status,
  });
  return ok(claim);
}

function exportsRoute(
  method: string,
  b: string | undefined,
  body: Json,
  actor: MockActor,
  headers: Headers,
  allow: Allow,
  denied: Denied,
): MockResult {
  if (!allow(EXPORT_ROLES)) return denied();
  if (method === "GET" && b === "resources") {
    const items = EXPORT_RESOURCES.filter(
      (r) => !RESOURCE_ROLES[r.name] || RESOURCE_ROLES[r.name]!.includes(actor.role),
    );
    return ok({ items });
  }
  if (method === "GET" && !b)
    return ok({ items: [...db.exports].sort((x, y) => y.created_at.localeCompare(x.created_at)) });
  if (method === "GET" && b) {
    const found = db.exports.find((e) => e.id === b);
    return found
      ? ok({ ...found, url_expires_at: iso(15 * 60_000) })
      : problem(404, "not_found", "Export not found.");
  }
  if (method === "POST" && !b) {
    const resource = String(body.resource ?? "");
    const spec = EXPORT_RESOURCES.find((r) => r.name === resource);
    if (!spec) return problem(422, "export_resource_unknown", `No export for ${resource}.`);
    const roles = RESOURCE_ROLES[resource];
    if (roles && !roles.includes(actor.role)) return denied();
    const format = String(body.format ?? "csv");
    if (!spec.formats.includes(format))
      return problem(422, "export_format_unsupported", `${resource} has no ${format}.`);
    if (!mockStepUpOk(headers, actor)) return stepUpRequired();
    db.seq += 1;
    const rows = 120 + Math.floor(rnd(`${resource}:${db.seq}`) * 3000);
    const header = spec.columns.join(",");
    const created: ExportJob = {
      id: `exp-${String(db.seq).padStart(4, "0")}`,
      resource,
      format,
      filters: (body.filters ?? {}) as Json,
      status: "ready",
      rows,
      size_bytes: rows * 118,
      filename: `${resource}-${new Date().toISOString().slice(0, 10)}.${format}`,
      url: `data:text/csv;charset=utf-8,${encodeURIComponent(`﻿${header}\n`)}`,
      url_expires_at: iso(15 * 60_000),
      created_at: new Date().toISOString(),
      created_by: actor.id,
    };
    db.exports.unshift(created);
    recordAudit(actor, "export.create", "export_job", created.id, null, { resource, format });
    return ok(created, 201);
  }
  return problem(405, "method_not_allowed", "Unsupported export call.");
}

function schedules(
  method: string,
  b: string | undefined,
  body: Json,
  actor: MockActor,
  headers: Headers,
  allow: Allow,
  denied: Denied,
): MockResult {
  if (!allow(SCHEDULE_ROLES)) return denied();
  if (method === "GET" && !b)
    return ok({ items: [...db.schedules].sort((x, y) => x.name.localeCompare(y.name)) });
  const cronOk = (cron: string) => /^(\S+\s+){4}\S+$/.test(cron.trim());
  if (method === "POST" && !b) {
    const cron = String(body.cron ?? "0 8 * * 1");
    if (!cronOk(cron)) return problem(422, "cron_invalid", "Five cron fields are required.");
    if (!mockStepUpOk(headers, actor)) return stepUpRequired();
    db.seq += 1;
    const created: Schedule = {
      id: `sched-${String(db.seq).padStart(4, "0")}`,
      name: String(body.name ?? ""),
      resource: String(body.resource ?? "orders"),
      format: String(body.format ?? "csv"),
      filters: (body.filters ?? {}) as Json,
      recipients: (body.recipients ?? []) as string[],
      cron,
      active: body.active !== false,
      last_run_at: null,
      next_run_at: iso(3 * D),
      created_at: new Date().toISOString(),
    };
    db.schedules.unshift(created);
    recordAudit(actor, "report_schedule.create", "report_schedule", created.id, null, { cron });
    return ok(created, 201);
  }
  const found = db.schedules.find((s) => s.id === b);
  if (!found) return problem(404, "not_found", "Schedule not found.");
  if (method === "PATCH") {
    if (body.cron !== undefined && !cronOk(String(body.cron)))
      return problem(422, "cron_invalid", "Five cron fields are required.");
    if (!mockStepUpOk(headers, actor)) return stepUpRequired();
    Object.assign(found, {
      name: body.name !== undefined ? String(body.name) : found.name,
      resource: body.resource !== undefined ? String(body.resource) : found.resource,
      format: body.format !== undefined ? String(body.format) : found.format,
      recipients: (body.recipients ?? found.recipients) as string[],
      cron: body.cron !== undefined ? String(body.cron) : found.cron,
      active: body.active !== undefined ? body.active === true : found.active,
    });
    recordAudit(actor, "report_schedule.update", "report_schedule", found.id, null, null);
    return ok(found);
  }
  if (method === "DELETE") {
    if (!mockStepUpOk(headers, actor)) return stepUpRequired();
    db.schedules = db.schedules.filter((s) => s.id !== b);
    recordAudit(actor, "report_schedule.delete", "report_schedule", String(b), null, null);
    return { status: 204 };
  }
  return problem(405, "method_not_allowed", "Unsupported schedule call.");
}

/** `POST /travel/claims/{id}/approve|reject` (routed here because travel() stays read-only). */
export function handleTravelDecision(
  method: string,
  path: string[],
  body: Json,
  actor: MockActor | null,
): MockResult | null {
  if (method !== "POST" || path[0] !== "travel" || path[1] !== "claims" || !path[2]) return null;
  const action = path[3];
  if (action !== "approve" && action !== "reject") return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  return decideClaim(path[2], action, body, actor);
}
