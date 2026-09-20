/**
 * AN-006 crop health, AN-007 diagnosis quality and DX-012 model releases — the console half of
 * `farmerapp/advisory` and `farmerapp/mlops` (docs/prs/M7-farmer-p1-api.md).
 *
 * AN-014: `/v1/analytics/crop-health` is **district level only** — no farm location and no
 * farmer identity ever reaches these screens, so the map draws districts, never farms.
 */
import { authedFetch } from "./api";

/** `x-roles` of getCropHealth / getDiagnosisQuality. */
export const QUALITY_ROLES: ReadonlyArray<string> = [
  "owner",
  "director",
  "tenant_admin",
  "auditor",
  "agronomist",
];
/** `x-roles` of listModelReleases; only agronomists and owners decide (step-up). */
export const RELEASE_READ_ROLES: ReadonlyArray<string> = [
  "agronomist",
  "owner",
  "director",
  "tenant_admin",
];
export const RELEASE_DECIDE_ROLES: ReadonlyArray<string> = ["agronomist", "owner"];

// ---- AN-006 crop health ---------------------------------------------------------------------

export interface CropHealthCell {
  district: string;
  crop_id: string;
  crop_code: string;
  crop_names: Record<string, string>;
  problem_id: string;
  problem_code: string;
  problem_type: string;
  problem_names: Record<string, string>;
  iso_year: number;
  iso_week: number;
  week_start: string;
  confirmed_cases: number;
  farmers_affected: number;
  prior_mean: number;
  outbreak: boolean;
  alert_id: string | null;
  /** District centroid, when the API knows one (graduated markers); never a farm location. */
  latitude?: number | null;
  longitude?: number | null;
}

export interface CropHealthOut {
  weeks: number;
  items: CropHealthCell[];
}

export interface CropHealthFilters {
  weeks?: number;
  district?: string;
  crop_id?: string;
}

// ---- AN-007 diagnosis quality ------------------------------------------------------------------

export interface EvaluationRun {
  id: string;
  model_name: string | null;
  model_version: string | null;
  ran_at: string;
  status: string;
  cases: number;
  top1_accuracy: number | null;
  corpus_answer_share: number | null;
  escalation_rate: number | null;
  hallucinated_out_of_scope: number | null;
  top1_delta_points: number | null;
  alerted: boolean;
  per_crop?: Array<{
    crop_id: string | null;
    crop_code: string;
    cases: number;
    top1_accuracy: number;
  }>;
  per_problem?: Array<{ problem_code: string; cases: number; top1_accuracy: number }>;
  error?: string | null;
}

export interface QualityUnknown {
  crop_id: string | null;
  crop_code: string | null;
  reason: string;
  cases: number;
}

export interface DiagnosisQuality {
  days: number;
  requests: number;
  answered_by_corpus: number;
  corpus_share: number | null;
  escalated: number;
  escalation_rate: number | null;
  llm_share: number | null;
  by_source: Record<string, number>;
  by_status: Record<string, number>;
  review: {
    sla_hours: number;
    reviewed: number;
    reviewed_within_sla: number;
    sla_rate: number | null;
    avg_review_hours: number | null;
    median_review_hours: number | null;
    open_queue: number;
    open_overdue: number;
  };
  top_unknowns: QualityUnknown[];
  latest_evaluation: EvaluationRun | null;
}

// ---- DX-012 model releases ----------------------------------------------------------------------

export const RELEASE_STATUSES = ["candidate", "approved", "rejected", "retired"] as const;
export type ReleaseStatus = (typeof RELEASE_STATUSES)[number];

export interface ModelRelease {
  id: string;
  model_name: string;
  model_version: string;
  status: ReleaseStatus | string;
  sha256: string;
  size_bytes: number;
  labels: string[];
  notes: string | null;
  created_at: string;
  approved_at: string | null;
  decided_by: string | null;
  decision_note: string | null;
  evaluation: EvaluationRun | null;
  /** Percentage points against the currently approved release (null without an evaluation). */
  top1_delta_points: number | null;
}

export interface CurrentModel {
  release_id: string;
  model_name: string;
  model_version: string;
  sha256: string;
  size_bytes: number;
  approved_at: string | null;
  labels: string[];
}

const qs = (params: Record<string, string | number | undefined>): string => {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params))
    if (v !== undefined && v !== "") sp.set(k, String(v));
  const s = sp.toString();
  return s ? `?${s}` : "";
};

export const mlopsApi = {
  cropHealth: (f: CropHealthFilters = {}) =>
    authedFetch<CropHealthOut>(
      `v1/analytics/crop-health${qs({ weeks: f.weeks, district: f.district, crop_id: f.crop_id })}`,
    ),
  quality: (days = 30) => authedFetch<DiagnosisQuality>(`v1/diagnoses/quality${qs({ days })}`),
  evaluations: (limit = 10) =>
    authedFetch<{ items: EvaluationRun[] }>(`v1/diagnoses/evaluations${qs({ limit })}`),
  evaluation: (id: string) => authedFetch<EvaluationRun>(`v1/diagnoses/evaluations/${id}`),
  releases: (status?: string) =>
    authedFetch<{ items: ModelRelease[] }>(`v1/models/releases${qs({ status })}`),
  currentModel: () => authedFetch<CurrentModel>("v1/models/on-device/current"),
  decide: (
    id: string,
    body: { decision: "approve" | "reject" | "retire"; note: string | null },
    headers: Record<string, string> = {},
  ) => authedFetch<ModelRelease>(`v1/models/releases/${id}/decision`, { body, headers }),
};

// ---- pure helpers ----------------------------------------------------------------------------

/** ISO weeks present in the data, newest first (`2026-W38`). */
export function weekKeys(items: ReadonlyArray<CropHealthCell>): string[] {
  const seen = new Map<string, string>();
  for (const c of items)
    seen.set(`${c.iso_year}-W${String(c.iso_week).padStart(2, "0")}`, c.week_start);
  return [...seen.keys()].sort().reverse();
}

export const weekKeyOf = (c: CropHealthCell): string =>
  `${c.iso_year}-W${String(c.iso_week).padStart(2, "0")}`;

export interface DistrictRollup {
  district: string;
  cases: number;
  farmers: number;
  outbreaks: number;
  latitude: number | null;
  longitude: number | null;
  cells: CropHealthCell[];
}

/** Confirmed problems per district for one ISO week (the choropleth / marker values). */
export function rollupByDistrict(
  items: ReadonlyArray<CropHealthCell>,
  week: string | undefined,
): DistrictRollup[] {
  const out = new Map<string, DistrictRollup>();
  for (const c of items) {
    if (week && weekKeyOf(c) !== week) continue;
    const row = out.get(c.district) ?? {
      district: c.district,
      cases: 0,
      farmers: 0,
      outbreaks: 0,
      latitude: c.latitude ?? null,
      longitude: c.longitude ?? null,
      cells: [],
    };
    row.cases += c.confirmed_cases;
    row.farmers += c.farmers_affected;
    if (c.outbreak) row.outbreaks += 1;
    if (row.latitude === null && c.latitude != null) row.latitude = c.latitude;
    if (row.longitude === null && c.longitude != null) row.longitude = c.longitude;
    row.cells.push(c);
    out.set(c.district, row);
  }
  return [...out.values()].sort(
    (a, b) => b.cases - a.cases || a.district.localeCompare(b.district),
  );
}

/** Five sequential bands for the choropleth, from the week's maximum (0 keeps the empty band). */
export const CHOROPLETH_STEPS = 5;

export function bandFor(cases: number, max: number): number {
  if (cases <= 0 || max <= 0) return 0;
  return Math.min(CHOROPLETH_STEPS, Math.ceil((cases / max) * CHOROPLETH_STEPS));
}

/** A cell is an outbreak when the API said so (>= 3 cases and >= 2x the prior 4-week mean). */
export function outbreakCells(items: ReadonlyArray<CropHealthCell>): CropHealthCell[] {
  return items.filter((c) => c.outbreak).sort((a, b) => b.week_start.localeCompare(a.week_start));
}
