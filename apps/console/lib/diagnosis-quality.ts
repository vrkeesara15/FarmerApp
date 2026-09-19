/**
 * C62 basic diagnosis quality figures (SPEC 5.1 AN-007 subset), computed in the browser from the
 * review queue and a date-bounded list of recent diagnoses. The API has no summary endpoint yet;
 * AN-007 (M7) replaces this with server-side figures and the test-set accuracy (DX-011).
 */
import type { Diagnosis } from "./diagnosis";

const H = 3_600_000;

export const AGE_BUCKETS = ["lt6", "h6to18", "h18to24", "gt24"] as const;
export type AgeBucket = (typeof AGE_BUCKETS)[number];

export function ageBucket(ageHours: number): AgeBucket {
  if (ageHours < 6) return "lt6";
  if (ageHours < 18) return "h6to18";
  if (ageHours < 24) return "h18to24";
  return "gt24";
}

export interface UnknownRow {
  cropId: string | null;
  /** `out_of_scope_reason`, or `llm_unknown` for a provisional answer without a label. */
  reason: string;
  count: number;
}

export interface QualitySummary {
  total: number;
  bySource: { corpus: number; llm: number; agronomist: number; none: number };
  /** corpus / answered with any source (null when nothing was answered). */
  corpusShare: number | null;
  /** Sent to the agronomist queue / processed diagnoses. */
  escalationRate: number | null;
  /** Reviewed within 24 h / reviewed (null when none reviewed). */
  reviewedIn24h: number | null;
  reviewed: number;
  queueAges: Record<AgeBucket, number>;
  topUnknowns: UnknownRow[];
}

const ESCALATED = new Set(["provisional", "out_of_scope", "confirmed", "corrected"]);

export function summariseQuality(
  recent: ReadonlyArray<
    Pick<
      Diagnosis,
      | "status"
      | "source"
      | "flagged"
      | "created_at"
      | "reviewed_at"
      | "crop_id"
      | "out_of_scope_reason"
      | "final_problem_id"
    >
  >,
  queue: ReadonlyArray<Pick<Diagnosis, "created_at">>,
  now: number,
  topN = 5,
): QualitySummary {
  const processed = recent.filter((d) => d.status !== "queued");
  const bySource = { corpus: 0, llm: 0, agronomist: 0, none: 0 };
  for (const d of processed) {
    const s =
      d.source === "corpus" || d.source === "llm" || d.source === "agronomist" ? d.source : "none";
    bySource[s] += 1;
  }
  const answered = bySource.corpus + bySource.llm + bySource.agronomist;
  const escalated = processed.filter(
    (d) => ESCALATED.has(d.status) || d.flagged || d.reviewed_at,
  ).length;
  const reviewed = processed.filter((d) => d.reviewed_at);
  const inSla = reviewed.filter(
    (d) => new Date(d.reviewed_at!).getTime() - new Date(d.created_at).getTime() <= 24 * H,
  ).length;

  const queueAges: Record<AgeBucket, number> = { lt6: 0, h6to18: 0, h18to24: 0, gt24: 0 };
  for (const d of queue) queueAges[ageBucket((now - new Date(d.created_at).getTime()) / H)] += 1;

  const unknowns = new Map<string, UnknownRow>();
  for (const d of processed) {
    const reason =
      d.status === "out_of_scope"
        ? (d.out_of_scope_reason ?? "no_match")
        : d.status === "provisional" && !d.final_problem_id
          ? "llm_unknown"
          : null;
    if (!reason) continue;
    const key = `${d.crop_id ?? ""}|${reason}`;
    const row = unknowns.get(key) ?? { cropId: d.crop_id, reason, count: 0 };
    row.count += 1;
    unknowns.set(key, row);
  }
  const topUnknowns = [...unknowns.values()]
    .sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason))
    .slice(0, topN);

  return {
    total: processed.length,
    bySource,
    corpusShare: answered ? bySource.corpus / answered : null,
    escalationRate: processed.length ? escalated / processed.length : null,
    reviewedIn24h: reviewed.length ? inSla / reviewed.length : null,
    reviewed: reviewed.length,
    queueAges,
    topUnknowns,
  };
}
