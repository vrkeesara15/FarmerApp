/**
 * Corpus manager (WC-007, SPEC 3.2): typed `/v1/corpus/*` calls, the draft -> reviewed ->
 * approved -> retired workflow and the helpers C61 uses. Shapes mirror apps/api/openapi.yaml
 * (`CorpusProblemOut`, `CorpusImageOut`, `CorpusVersionsOut`, ...). Only approved problems with
 * approved images are served to production (the kNN never sees anything else).
 */
import { authedFetch } from "./api";
import { LOCALES } from "./i18n";

/** Readers (x-roles of listCorpusProblems) and the only writer (SPEC 2.6). */
export const CORPUS_READ_ROLES: ReadonlyArray<string> = ["agronomist", "director", "owner"];
export const CORPUS_WRITE_ROLES: ReadonlyArray<string> = ["agronomist"];

export const CORPUS_STATUSES = ["draft", "reviewed", "approved", "retired"] as const;
export type CorpusStatus = (typeof CORPUS_STATUSES)[number];
export const CORPUS_SOURCES = ["internal", "public"] as const;
export type CorpusSource = (typeof CORPUS_SOURCES)[number];
export const IMAGE_PARTS = ["leaf", "stem", "fruit", "whole"] as const;
export type ImagePart = (typeof IMAGE_PARTS)[number];
export const IMAGE_SEVERITIES = ["low", "medium", "high"] as const;
export type ImageSeverity = (typeof IMAGE_SEVERITIES)[number];
export const CROP_STAGES = ["sown", "vegetative", "flowering", "fruiting", "maturity"] as const;
export const SEASONS = ["kharif", "rabi", "zaid"] as const;
export const PROBLEM_TYPES = ["disease", "pest", "nutrient", "abiotic"] as const;

/** Same table as apps/api/farmerapp/diagnosis/models.py CORPUS_TRANSITIONS. */
export const CORPUS_TRANSITIONS: Readonly<Record<CorpusStatus, ReadonlyArray<CorpusStatus>>> = {
  draft: ["reviewed", "retired"],
  reviewed: ["approved", "draft", "retired"],
  approved: ["retired"],
  retired: [],
};

/** Moves offered as buttons, in this order (forward first). */
const ACTION_ORDER: ReadonlyArray<CorpusStatus> = ["reviewed", "approved", "draft", "retired"];

/**
 * Workflow actions a role may take on an entry in `status`: agronomists follow the state
 * machine; owners and directors read only (no actions).
 */
export function corpusActions(status: CorpusStatus, role: string | undefined): CorpusStatus[] {
  if (!role || !CORPUS_WRITE_ROLES.includes(role)) return [];
  const allowed = CORPUS_TRANSITIONS[status] ?? [];
  return ACTION_ORDER.filter((s) => allowed.includes(s));
}

/** Approved and retired entries are immutable (API 409 `corpus_entry_locked`). */
export function isEditable(status: CorpusStatus): boolean {
  return status === "draft" || status === "reviewed";
}

/** Moves that change what production serves, so the corpus version is bumped. */
export function bumpsVersion(from: CorpusStatus, to: CorpusStatus): boolean {
  return to === "approved" || from === "approved";
}

// ---- shapes ------------------------------------------------------------------------------
export interface CorpusProblem {
  id: string;
  pest_or_disease_id: string;
  pest_code: string | null;
  crop_id: string;
  problem_type: string;
  names: Record<string, string>;
  symptoms: Record<string, string[]>;
  cultural_practices: Record<string, string[]>;
  status: CorpusStatus;
  source: CorpusSource | string;
  labelled_by: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  approved_by: string | null;
  approved_at: string | null;
  approved_in_version: number | null;
  retired_at: string | null;
  notes: string | null;
  image_counts: Partial<Record<CorpusStatus, number>>;
  created_at: string;
  updated_at: string;
  version: number;
}

export interface CorpusProblemPage {
  items: CorpusProblem[];
  next_cursor?: string | null;
  corpus_version: number;
}

export interface CorpusImage {
  id: string;
  problem_id: string;
  crop_id: string;
  blob_uri: string;
  sha256: string;
  encoder_name: string;
  encoder_version: string;
  stage: string | null;
  part: string | null;
  severity: string | null;
  region: string | null;
  season: string | null;
  source: string;
  status: CorpusStatus;
  labelled_by: string | null;
  approved_by: string | null;
  approved_at: string | null;
  approved_in_version: number | null;
  from_diagnosis_id: string | null;
  created_at: string;
  version: number;
  signed_url?: string | null;
}

export interface CorpusImagePage {
  items: CorpusImage[];
  next_cursor?: string | null;
}

export interface CorpusVersion {
  id: string;
  version: number;
  approved_by: string | null;
  note: string | null;
  changes: { problems?: string[]; images?: string[]; retired?: string[] };
  created_at: string;
}

export interface CorpusVersions {
  current: number;
  items: CorpusVersion[];
}

export interface CorpusProblemInput {
  pest_or_disease_id: string;
  crop_id: string;
  names: Record<string, string>;
  symptoms: Record<string, string[]>;
  cultural_practices?: Record<string, string[]>;
  source: CorpusSource;
  notes?: string | null;
}

export type CorpusProblemPatch = Partial<
  Pick<CorpusProblemInput, "names" | "symptoms" | "cultural_practices" | "notes">
>;

export interface CorpusImageInput {
  blob_uri: string;
  sha256?: string | null;
  stage?: string | null;
  part?: ImagePart | null;
  severity?: ImageSeverity | null;
  region?: string | null;
  season?: string | null;
  source: CorpusSource;
}

export interface CorpusProblemFilters {
  crop_id?: string;
  status?: CorpusStatus[];
  source?: CorpusSource;
}

// ---- helpers -----------------------------------------------------------------------------
/** "What production uses": approved problems (their approved images are what the kNN sees). */
export const PRODUCTION_STATUSES: ReadonlyArray<CorpusStatus> = ["approved"];

export function isServed(problem: Pick<CorpusProblem, "status">): boolean {
  return PRODUCTION_STATUSES.includes(problem.status);
}

/** Approved images of an approved problem: the only rows production serves. */
export function servedImageCount(problem: Pick<CorpusProblem, "status" | "image_counts">): number {
  return isServed(problem) ? (problem.image_counts.approved ?? 0) : 0;
}

/** Case-insensitive match on the problem's names in every language and its code. */
export function matchesProblem(
  problem: Pick<CorpusProblem, "names" | "pest_code">,
  query: string,
): boolean {
  const q = query.trim().toLocaleLowerCase();
  if (!q) return true;
  const hay = [...Object.values(problem.names ?? {}), problem.pest_code ?? ""];
  return hay.some((v) => v.toLocaleLowerCase().includes(q));
}

/** One symptom per line -> list (blank lines dropped). */
export function linesToList(text: string): string[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
}

/** Drops empty languages so the API only stores real translations (en stays required). */
export function compactNames(names: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const l of LOCALES) {
    const v = names[l]?.trim();
    if (v) out[l] = v;
  }
  return out;
}

export function compactLists(lists: Record<string, string>): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const l of LOCALES) {
    const v = linesToList(lists[l] ?? "");
    if (v.length) out[l] = v;
  }
  return out;
}

function query(params: Record<string, string | string[] | undefined>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (Array.isArray(v)) for (const x of v) p.append(k, x);
    else if (v) p.set(k, v);
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

// ---- calls -------------------------------------------------------------------------------
export const corpusApi = {
  problems: (f: CorpusProblemFilters = {}) =>
    authedFetch<CorpusProblemPage>(
      `v1/corpus/problems${query({ crop_id: f.crop_id, status: f.status, source: f.source, limit: "200" })}`,
    ),
  problem: (id: string) => authedFetch<CorpusProblem>(`v1/corpus/problems/${id}`),
  createProblem: (body: CorpusProblemInput) =>
    authedFetch<CorpusProblem>("v1/corpus/problems", { body }),
  updateProblem: (id: string, body: CorpusProblemPatch) =>
    authedFetch<CorpusProblem>(`v1/corpus/problems/${id}`, { method: "PATCH", body }),
  transitionProblem: (id: string, to: CorpusStatus, note: string | null) =>
    authedFetch<CorpusProblem>(`v1/corpus/problems/${id}/transition`, { body: { to, note } }),
  images: (problemId: string, status?: CorpusStatus[]) =>
    authedFetch<CorpusImagePage>(
      `v1/corpus/problems/${problemId}/images${query({ status, limit: "200" })}`,
    ),
  addImage: (problemId: string, body: CorpusImageInput) =>
    authedFetch<CorpusImage>(`v1/corpus/problems/${problemId}/images`, { body }),
  transitionImage: (id: string, to: CorpusStatus, note: string | null) =>
    authedFetch<CorpusImage>(`v1/corpus/images/${id}/transition`, { body: { to, note } }),
  approve: (body: { problem_ids: string[]; image_ids: string[]; note: string | null }) =>
    authedFetch<CorpusVersion>("v1/corpus/approvals", { body }),
  versions: () => authedFetch<CorpusVersions>("v1/corpus/versions"),
};
