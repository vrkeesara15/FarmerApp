/**
 * WC-009 targets and incentives (C90). Typed `/v1/targets`, `/v1/incentive-rules`,
 * `/v1/incentives/*` calls plus the pure rule-document helpers the editor uses.
 *
 * VV-005: eligibility and the `verified_visits` metric count **verified visits only** unless the
 * rule document widens `count_visit_statuses`; `verifiedVisitsNote()` decides which of the two
 * notes C90 shows so the reader is never left guessing what a visit count means.
 * Money is integer paise everywhere (CLAUDE.md).
 */
import { authedFetch } from "./api";

export const TARGET_SUBJECTS = ["officer", "store"] as const;
export type TargetSubject = (typeof TARGET_SUBJECTS)[number];

export const TARGET_METRICS = [
  "visits_verified",
  "new_farmers",
  "sales_paise",
  "collections_paise",
  "own_brand_share_bp",
] as const;
export type TargetMetric = (typeof TARGET_METRICS)[number];

/** Roles that may edit targets and publish rule versions (`x-roles` of putTargets). */
export const INCENTIVE_WRITE_ROLES: ReadonlyArray<string> = ["owner", "director", "tenant_admin"];
/** Only owners and directors may close a month (step-up). */
export const INCENTIVE_CLOSE_ROLES: ReadonlyArray<string> = ["owner", "director"];
export const INCENTIVE_READ_ROLES: ReadonlyArray<string> = [
  ...INCENTIVE_WRITE_ROLES,
  "auditor",
  "accountant",
  "cluster_head",
];

export interface TargetRow {
  subject_type: TargetSubject;
  subject_id: string;
  subject_name: string;
  visits_verified: number | null;
  new_farmers: number | null;
  sales_paise: number | null;
  collections_paise: number | null;
  own_brand_share_bp: number | null;
}

export interface TargetsOut {
  month: string;
  items: TargetRow[];
}

export interface TargetPatch {
  subject_type: TargetSubject;
  subject_id: string;
  visits_verified?: number | null;
  new_farmers?: number | null;
  sales_paise?: number | null;
  collections_paise?: number | null;
  own_brand_share_bp?: number | null;
}

// ---- rule document -------------------------------------------------------------------------

export const COMPONENT_KINDS = [
  "per_unit",
  "slab_per_unit",
  "slab_flat",
  "percent",
  "threshold",
] as const;
export type ComponentKind = (typeof COMPONENT_KINDS)[number];

export const RULE_METRICS = [
  "verified_visits",
  "visits",
  "new_farmers",
  "sales_paise",
  "own_brand_sales_paise",
  "own_brand_share",
  "collections_paise",
] as const;
export type RuleMetric = (typeof RULE_METRICS)[number];

/** Metrics whose value is money in paise (a `percent` component only applies to these). */
export const PAISE_METRICS: ReadonlyArray<string> = [
  "sales_paise",
  "own_brand_sales_paise",
  "collections_paise",
];

export interface RuleSlab {
  from: number;
  to?: number | null;
  rate_paise?: number;
  amount_paise?: number;
}

export interface RuleComponent {
  id: string;
  metric: string;
  kind: ComponentKind;
  slabs?: RuleSlab[];
  rate_paise?: number;
  rate_bp?: number;
  threshold?: number;
  amount_paise?: number;
  cap_paise?: number | null;
}

export interface RuleMultiplier {
  metric: string;
  gte: number;
  factor: number;
}

export interface RuleEligibility {
  min_verified_visits?: number;
  count_visit_statuses?: string[];
}

export interface RuleDefinition {
  eligibility?: RuleEligibility;
  components: RuleComponent[];
  multipliers?: RuleMultiplier[];
  cap_paise?: number | null;
  clawback?: { cancelled_orders?: boolean };
}

export interface RuleSet {
  id: string;
  name: string;
  version: number;
  status: "draft" | "active" | "retired" | string;
  definition: RuleDefinition;
  activated_at: string | null;
  created_at: string;
  created_by: string | null;
}

export interface IncentiveLine {
  component: string;
  metric: string;
  value: number;
  amount_paise: number;
  capped: boolean;
  note: string | null;
}

export interface IncentiveOut {
  officer_id: string;
  officer_name?: string | null;
  period_start: string;
  period_end: string;
  status: "preview" | "closed";
  rule_set_id: string | null;
  rule_version: number | null;
  eligible: boolean;
  metrics: Record<string, number>;
  targets: Record<string, number | null>;
  lines: IncentiveLine[];
  gross_paise: number;
  clawback_paise: number;
  amount_paise: number;
  reasons: string[];
}

export interface PayoutsOut {
  month: string;
  items: IncentiveOut[];
  total_paise: number;
}

const qs = (params: Record<string, string | undefined>): string => {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v) sp.set(k, v);
  const s = sp.toString();
  return s ? `?${s}` : "";
};

export const incentivesApi = {
  targets: (month: string, subjectType?: TargetSubject) =>
    authedFetch<TargetsOut>(`v1/targets${qs({ month, subject_type: subjectType })}`),
  putTargets: (month: string, items: TargetPatch[], headers: Record<string, string> = {}) =>
    authedFetch<TargetsOut>("v1/targets", { method: "PUT", body: { month, items }, headers }),
  rules: () => authedFetch<{ items: RuleSet[] }>("v1/incentive-rules"),
  rule: (id: string) => authedFetch<RuleSet>(`v1/incentive-rules/${id}`),
  createRule: (
    body: { name: string; definition: RuleDefinition; activate?: boolean },
    headers: Record<string, string> = {},
  ) => authedFetch<RuleSet>("v1/incentive-rules", { body, headers }),
  activateRule: (id: string, headers: Record<string, string> = {}) =>
    authedFetch<RuleSet>(`v1/incentive-rules/${id}/activate`, { method: "POST", headers }),
  preview: (params: { month: string; officer_id?: string; rule_set_id?: string }) =>
    authedFetch<IncentiveOut>(`v1/incentives/preview${qs(params)}`),
  previewDefinition: (body: { officer_id: string; month: string; definition: RuleDefinition }) =>
    authedFetch<IncentiveOut>("v1/incentives/preview", { body }),
  payouts: (month: string) => authedFetch<PayoutsOut>(`v1/incentives/payouts${qs({ month })}`),
  close: (month: string, headers: Record<string, string> = {}) =>
    authedFetch<PayoutsOut>("v1/incentives/close", { body: { month }, headers }),
};

// ---- pure helpers (unit-tested) --------------------------------------------------------------

export interface RuleIssue {
  /** Index in `definition.components`, or null for a document-level problem. */
  component: number | null;
  /** i18n key suffix under `incentives.ruleError.` */
  code: string;
}

const isInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v);
const nonNegative = (v: unknown): boolean => typeof v === "number" && v >= 0 && Number.isFinite(v);

/**
 * Validates a rule document the way `farmerapp/incentives/rules.py` does, so the editor can
 * refuse to publish before the API answers 422 `invalid_incentive_rules`.
 */
export function validateDefinition(def: RuleDefinition): RuleIssue[] {
  const issues: RuleIssue[] = [];
  if (!Array.isArray(def.components) || def.components.length === 0)
    issues.push({ component: null, code: "noComponents" });
  const seen = new Set<string>();
  (def.components ?? []).forEach((c, i) => {
    if (!c.id || !/^[a-z0-9_]+$/.test(c.id)) issues.push({ component: i, code: "idInvalid" });
    else if (seen.has(c.id)) issues.push({ component: i, code: "idDuplicate" });
    seen.add(c.id);
    if (!(RULE_METRICS as readonly string[]).includes(c.metric))
      issues.push({ component: i, code: "metricUnknown" });
    if (!(COMPONENT_KINDS as readonly string[]).includes(c.kind))
      issues.push({ component: i, code: "kindUnknown" });
    switch (c.kind) {
      case "per_unit":
        if (!isInt(c.rate_paise) || c.rate_paise < 0)
          issues.push({ component: i, code: "rateRequired" });
        break;
      case "percent":
        if (!isInt(c.rate_bp) || c.rate_bp <= 0)
          issues.push({ component: i, code: "rateBpRequired" });
        if (!PAISE_METRICS.includes(c.metric))
          issues.push({ component: i, code: "percentNeedsMoney" });
        break;
      case "threshold":
        if (!nonNegative(c.threshold)) issues.push({ component: i, code: "thresholdRequired" });
        if (!isInt(c.amount_paise) || c.amount_paise < 0)
          issues.push({ component: i, code: "amountRequired" });
        break;
      case "slab_per_unit":
      case "slab_flat": {
        const slabs = c.slabs ?? [];
        if (slabs.length === 0) issues.push({ component: i, code: "slabsRequired" });
        let previousTo: number | null = 0;
        slabs.forEach((s, si) => {
          if (!nonNegative(s.from)) issues.push({ component: i, code: "slabFrom" });
          if (si === 0 && s.from !== 0) issues.push({ component: i, code: "slabStart" });
          if (si > 0 && previousTo !== null && s.from !== previousTo)
            issues.push({ component: i, code: "slabGap" });
          if (s.to != null && s.to <= s.from) issues.push({ component: i, code: "slabOrder" });
          const amount = c.kind === "slab_per_unit" ? s.rate_paise : s.amount_paise;
          if (!isInt(amount) || amount < 0) issues.push({ component: i, code: "slabAmount" });
          previousTo = s.to ?? null;
        });
        if (previousTo !== null) issues.push({ component: i, code: "slabOpenEnd" });
        break;
      }
      default:
        break;
    }
    if (c.cap_paise != null && (!isInt(c.cap_paise) || c.cap_paise <= 0))
      issues.push({ component: i, code: "capInvalid" });
  });
  (def.multipliers ?? []).forEach(() => undefined);
  for (const m of def.multipliers ?? []) {
    if (
      !m.metric.startsWith("attainment.") &&
      !(RULE_METRICS as readonly string[]).includes(m.metric)
    )
      issues.push({ component: null, code: "multiplierMetric" });
    if (!(typeof m.factor === "number" && m.factor > 0))
      issues.push({ component: null, code: "multiplierFactor" });
  }
  if (def.cap_paise != null && (!isInt(def.cap_paise) || def.cap_paise <= 0))
    issues.push({ component: null, code: "capInvalid" });
  const statuses = def.eligibility?.count_visit_statuses;
  if (statuses && statuses.length === 0)
    issues.push({ component: null, code: "visitStatusesEmpty" });
  return issues;
}

/**
 * Which "verified visits only" note C90 shows: the default document counts verified visits
 * only (VV-005); a document that widens `count_visit_statuses` is called out instead, with the
 * statuses it counts, so nobody reads a wider count as a verified one.
 */
export function verifiedVisitsNote(def: RuleDefinition | null | undefined): {
  key: "verifiedOnly" | "widened";
  statuses: string[];
} {
  const statuses = def?.eligibility?.count_visit_statuses ?? ["verified"];
  const verifiedOnly = statuses.length === 1 && statuses[0] === "verified";
  return { key: verifiedOnly ? "verifiedOnly" : "widened", statuses };
}

/** `2026-09` -> the previous month, so C90 opens on a month that has ended. */
export function previousMonth(today: Date = new Date()): string {
  const d = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1));
  d.setUTCMonth(d.getUTCMonth() - 1);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

export function isMonth(value: string): boolean {
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(value);
}

/** Last `n` months ending with the month before `today`, newest first. */
export function recentMonths(n = 12, today: Date = new Date()): string[] {
  const out: string[] = [];
  const d = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1));
  for (let i = 0; i < n; i++) {
    d.setUTCMonth(d.getUTCMonth() - 1);
    out.push(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`);
  }
  return out;
}

/** A starting document for a tenant with no rules yet (the SPEC example, halved rates). */
export function starterDefinition(): RuleDefinition {
  return {
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
    ],
    multipliers: [{ metric: "attainment.sales_paise", gte: 1, factor: 1.1 }],
    cap_paise: 1500000,
    clawback: { cancelled_orders: true },
  };
}
