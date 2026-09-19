/**
 * Crop doctor review (WC-006, DX-005, DX-006): typed `/v1/diagnoses*` calls and the helpers C60
 * (agronomist review queue) and C62 (diagnosis quality) share. Shapes mirror
 * apps/api/openapi.yaml (`ReviewQueuePage`, `ReviewQueueItem`, `DiagnosisDetailOut`,
 * `DiagnosisPage`, `ReviewIn`) and docs/prs/M6-diagnosis-api.md.
 */
import { authedFetch } from "./api";

/** Review queue readers (x-roles of getReviewQueue); only agronomists review. */
export const REVIEW_QUEUE_ROLES: ReadonlyArray<string> = ["agronomist", "owner"];
export const REVIEW_ROLES: ReadonlyArray<string> = ["agronomist"];

export const CONFIDENCES = ["high", "medium", "low"] as const;
export type Confidence = (typeof CONFIDENCES)[number];

export const DIAGNOSIS_STATUSES = [
  "queued",
  "answered",
  "provisional",
  "confirmed",
  "corrected",
  "out_of_scope",
] as const;
export type DiagnosisStatus = (typeof DIAGNOSIS_STATUSES)[number];

export const REVIEW_ACTIONS = ["confirm", "correct", "not_diagnosable"] as const;
export type ReviewAction = (typeof REVIEW_ACTIONS)[number];

/** DX-006: queue ageing alert at 18 h (OPS-009), review SLA 24 h. */
export const SLA_WARNING_HOURS = 18;
export const SLA_BREACH_HOURS = 24;
const HOUR = 3_600_000;

// ---- shapes ------------------------------------------------------------------------------
export interface DiagnosisPhoto {
  blob_uri: string;
  sha256: string;
  quality?: Record<string, unknown> | null;
  signed_url?: string | null;
}

export interface LocalisedProblem {
  id: string;
  pest_or_disease_id?: string;
  code?: string;
  type?: string;
  crop_id?: string;
  names: Record<string, string>;
  symptoms?: Record<string, string[]>;
}

export interface DiagnosisResult {
  problem?: LocalisedProblem | null;
  confidence?: string | null;
  visible_symptoms?: string[];
  [key: string]: unknown;
}

export interface ScoreCandidate {
  problem_id: string;
  score: number;
  votes: number;
}

export interface LlmScores {
  model?: string;
  status?: string;
  problem_id?: string | null;
  confidence?: string | null;
  reasoning?: string | null;
  not_a_plant?: boolean;
}

export interface DiagnosisScores {
  neighbours?: Array<{ image_id: string; problem_id: string; similarity: number }>;
  thresholds?: {
    t1: number;
    agreement: number;
    min_similarity: number;
    config_version: number;
    crop_id?: string | null;
  };
  decision?: Record<string, unknown>;
  top1?: number;
  votes?: Record<string, number>;
  candidates?: ScoreCandidate[];
  llm?: LlmScores | null;
}

export interface DiagnosisReview {
  id: string;
  actor_id: string | null;
  action: ReviewAction | string;
  from_status: string;
  to_status: string;
  from_problem_id: string | null;
  to_problem_id: string | null;
  note: string | null;
  add_to_corpus: boolean;
  corpus_image_ids: string[];
  created_at: string;
}

export interface Diagnosis {
  id: string;
  subject: string;
  farmer_id: string;
  crop_plot_id: string | null;
  requested_by: string | null;
  crop_id: string | null;
  crop_detected_on_device: { code?: string; confidence?: number } | null;
  district: string | null;
  season: string | null;
  crop_stage: string | null;
  status: DiagnosisStatus;
  source: "corpus" | "llm" | "agronomist" | string | null;
  confidence: Confidence | string | null;
  provisional: boolean;
  can_buy: boolean;
  cta: string | null;
  message_key: string | null;
  result: DiagnosisResult | null;
  final_problem_id: string | null;
  out_of_scope_reason: string | null;
  flagged: boolean;
  model_versions: { encoder?: string | null; on_device?: string | null; llm?: string | null };
  corpus_version: number | null;
  images: DiagnosisPhoto[];
  captured_at: string | null;
  answered_at: string | null;
  reviewed_at: string | null;
  created_at: string;
  updated_at: string;
  version: number;
  llm_used?: boolean;
  scores?: DiagnosisScores | null;
  reviews?: DiagnosisReview[];
  reviewed_by?: string | null;
  /** DX-001 block the app sent (reviewer roles only; DX-005 provenance). */
  on_device?: OnDeviceBlock | null;
  /** FM-006 ask-expert on an answered case. */
  expert_requested_at?: string | null;
  expert_requested_by?: string | null;
  expert_note?: string | null;
}

export interface OnDeviceBlock {
  model: string;
  model_version: string;
  model_sha256?: string;
  fallback?: string | null;
  plant_score?: number | null;
  quality?: { ok?: number | null; blurry?: number | null; dark?: number | null } | null;
  crop_scores?: Record<string, number> | null;
  heuristic?: { blur_score?: number | null; brightness?: number | null } | null;
  latency_ms?: number | null;
}

export interface ReviewQueueItem extends Diagnosis {
  age_hours: number;
  overdue: boolean;
}

export interface ReviewQueueCounts {
  total: number;
  overdue: number;
  by_confidence: Record<string, number>;
}

export interface ReviewQueuePage {
  items: ReviewQueueItem[];
  next_cursor?: string | null;
  counts: ReviewQueueCounts;
}

export interface DiagnosisPage {
  items: Diagnosis[];
  next_cursor?: string | null;
}

export interface ReviewInput {
  action: ReviewAction;
  problem_id?: string | null;
  note: string;
  add_to_corpus: boolean;
}

export interface ReviewQueueFilters {
  crop_id?: string;
  confidence?: Confidence[];
  min_age_hours?: number;
  flagged?: boolean;
  cursor?: string | null;
  limit?: number;
}

export function reviewQueueQuery(f: ReviewQueueFilters): string {
  const p = new URLSearchParams();
  if (f.crop_id) p.set("crop_id", f.crop_id);
  for (const c of f.confidence ?? []) p.append("confidence", c);
  if (f.min_age_hours !== undefined) p.set("min_age_hours", String(f.min_age_hours));
  if (f.flagged) p.set("flagged", "true");
  if (f.cursor) p.set("cursor", f.cursor);
  if (f.limit) p.set("limit", String(f.limit));
  const s = p.toString();
  return s ? `?${s}` : "";
}

// ---- SLA (DX-006) ------------------------------------------------------------------------
export type SlaLevel = "ok" | "warning" | "breach";

export interface ReviewSla {
  level: SlaLevel;
  /** Hours since the request (created_at). */
  ageHours: number;
  /** Milliseconds until the 24 h SLA; negative once breached. */
  remainingMs: number;
  /** Countdown to the SLA ("5h 20m"), or time since the breach. */
  text: string;
}

const pad = (n: number) => String(n).padStart(2, "0");

/** "1d 02h", "5h 07m", "12m 09s" for an absolute duration. */
export function formatSpan(ms: number): string {
  const total = Math.floor(Math.abs(ms) / 1000);
  const d = Math.floor(total / 86_400);
  const h = Math.floor((total % 86_400) / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (d > 0) return `${d}d ${pad(h)}h`;
  if (h > 0) return `${h}h ${pad(m)}m`;
  return `${m}m ${pad(s)}s`;
}

/**
 * Review SLA of a queued diagnosis: warning from 18 h (the OPS-009 ageing alert, also when the
 * API already says `overdue`), breach at 24 h. Age counts from `created_at` like the API.
 */
export function reviewSla(
  createdAt: string,
  now: number,
  opts: { overdue?: boolean } = {},
): ReviewSla {
  const created = new Date(createdAt).getTime();
  const ageMs = Math.max(0, now - created);
  const remainingMs = created + SLA_BREACH_HOURS * HOUR - now;
  const level: SlaLevel =
    remainingMs <= 0
      ? "breach"
      : ageMs >= SLA_WARNING_HOURS * HOUR || opts.overdue
        ? "warning"
        : "ok";
  return { level, ageHours: ageMs / HOUR, remainingMs, text: formatSpan(remainingMs) };
}

/** Age filter options of the queue (hours; `min_age_hours`). */
export const AGE_FILTERS = [6, 12, 18, 24] as const;

// ---- candidates (DX-003 / DX-005) --------------------------------------------------------
export interface CandidateRow {
  problemId: string;
  /** Best cosine similarity of the problem's corpus images. */
  score: number;
  /** Neighbours of the problem among the top 10. */
  votes: number;
  /** votes / all votes of the top 10 (0..1). */
  voteShare: number;
  /** The corpus proposal (top-1's problem). */
  proposed: boolean;
  /** The LLM picked this candidate. */
  llmChoice: boolean;
}

/** Model candidates with similarity and vote share, best score first. */
export function candidateRows(scores: DiagnosisScores | null | undefined): CandidateRow[] {
  if (!scores) return [];
  const candidates = scores.candidates ?? [];
  const votes = scores.votes ?? {};
  const totalVotes =
    Object.values(votes).reduce((a, b) => a + b, 0) || candidates.reduce((a, c) => a + c.votes, 0);
  const proposal =
    (scores.decision?.problem_id as string | null | undefined) ?? candidates[0]?.problem_id;
  const llm = scores.llm?.problem_id ?? null;
  return [...candidates]
    .sort((a, b) => b.score - a.score || b.votes - a.votes)
    .map((c) => {
      const v = votes[c.problem_id] ?? c.votes;
      return {
        problemId: c.problem_id,
        score: c.score,
        votes: v,
        voteShare: totalVotes > 0 ? v / totalVotes : 0,
        proposed: c.problem_id === proposal,
        llmChoice: c.problem_id === llm,
      };
    });
}

/** "0.934" — cosine similarity with three decimals. */
export const formatScore = (score: number): string => score.toFixed(3);

// ---- names -------------------------------------------------------------------------------
/** A problem's name in `locale`, falling back to English, then its code. */
export function localName(
  names: Record<string, string> | null | undefined,
  locale: string,
  fallback = "",
): string {
  return names?.[locale] || names?.en || fallback;
}

// ---- review form (WC-006) ----------------------------------------------------------------
export interface ReviewDraft {
  action: ReviewAction | "";
  problemId: string;
  note: string;
  addToCorpus: boolean;
}

export type ReviewErrors = Partial<Record<"action" | "problem" | "note", "required" | "same">>;

/**
 * Client validation mirroring `ReviewIn` (422 `review_invalid`): an action, a note (1-2000),
 * and a corpus problem to `correct` that differs from the current label.
 */
export function validateReview(draft: ReviewDraft, currentProblemId?: string | null): ReviewErrors {
  const errors: ReviewErrors = {};
  if (!draft.action) errors.action = "required";
  if (draft.action === "correct") {
    if (!draft.problemId) errors.problem = "required";
    else if (currentProblemId && draft.problemId === currentProblemId) errors.problem = "same";
  }
  if (!draft.note.trim()) errors.note = "required";
  return errors;
}

export function reviewBody(draft: ReviewDraft): ReviewInput {
  return {
    action: draft.action as ReviewAction,
    problem_id: draft.action === "correct" ? draft.problemId : null,
    note: draft.note.trim(),
    add_to_corpus: draft.action === "not_diagnosable" ? false : draft.addToCorpus,
  };
}

// ---- calls -------------------------------------------------------------------------------
export const diagnosisApi = {
  queue: (f: ReviewQueueFilters) =>
    authedFetch<ReviewQueuePage>(`v1/diagnoses/review-queue${reviewQueueQuery(f)}`),
  get: (id: string) => authedFetch<Diagnosis>(`v1/diagnoses/${id}`),
  list: (opts: { status?: DiagnosisStatus[]; cursor?: string | null; limit?: number } = {}) => {
    const p = new URLSearchParams();
    for (const s of opts.status ?? []) p.append("status", s);
    if (opts.cursor) p.set("cursor", opts.cursor);
    p.set("limit", String(opts.limit ?? 200));
    return authedFetch<DiagnosisPage>(`v1/diagnoses?${p.toString()}`);
  },
  review: (id: string, body: ReviewInput) =>
    authedFetch<Diagnosis>(`v1/diagnoses/${id}/review`, { body }),
};
