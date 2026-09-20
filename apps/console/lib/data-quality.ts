/**
 * AN-009 data quality: flag volume by rule, resolution time and repeat subjects, summarised in
 * the browser from `/v1/flags` (the marts `mart_flags_weekly` / `mart_flag_repeat_offenders`
 * exist, but no summary endpoint does yet — this is the same approach C62 used before AN-007).
 * Shown as the "Data quality" tab of the C70 inbox.
 */
import { isResolved, type Flag, type FlagSeverity } from "./flags";

const H = 3_600_000;

/** SPEC 6.1 outcome labels: a flag resolved as `resolved_valid` was a false positive. */
export const FALSE_POSITIVE_STATUS = "resolved_valid";

export interface RuleRow {
  rule: string;
  total: number;
  open: number;
  resolved: number;
  falsePositives: number;
  /** Mean hours from raised to resolved (null when nothing is resolved). */
  avgResolutionHours: number | null;
  /** Share of resolved flags closed as false positives (null when nothing is resolved). */
  falsePositiveRate: number | null;
}

export interface RepeatSubject {
  subject_type: string;
  subject_id: string;
  count: number;
  rules: string[];
  lastAt: string;
}

export interface DataQualitySummary {
  total: number;
  open: number;
  resolved: number;
  overdue: number;
  bySeverity: Record<FlagSeverity, number>;
  byRule: RuleRow[];
  avgResolutionHours: number | null;
  medianResolutionHours: number | null;
  falsePositiveRate: number | null;
  repeatSubjects: RepeatSubject[];
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2;
}

const mean = (values: number[]): number | null =>
  values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;

/** Hours between raising and resolving a flag (null while it is open). */
export function resolutionHours(flag: Pick<Flag, "created_at" | "resolved_at">): number | null {
  if (!flag.resolved_at) return null;
  const ms = new Date(flag.resolved_at).getTime() - new Date(flag.created_at).getTime();
  return Number.isFinite(ms) ? ms / H : null;
}

/** `repeatMin` flags on the same subject inside `windowDays` (AN-009 repeat offenders). */
export function summariseDataQuality(
  flags: ReadonlyArray<Flag>,
  now: number = Date.now(),
  { repeatMin = 2, windowDays = 90, topSubjects = 10 } = {},
): DataQualitySummary {
  const bySeverity: Record<FlagSeverity, number> = { high: 0, medium: 0, low: 0 };
  const rules = new Map<string, { flags: Flag[] }>();
  const subjects = new Map<string, RepeatSubject>();
  const since = now - windowDays * 24 * H;
  let open = 0;
  let overdue = 0;
  const durations: number[] = [];

  for (const f of flags) {
    if (f.severity in bySeverity) bySeverity[f.severity as FlagSeverity] += 1;
    const resolved = isResolved(f.status);
    if (!resolved) {
      open += 1;
      if (f.overdue) overdue += 1;
    }
    const bucket = rules.get(f.rule_id) ?? { flags: [] };
    bucket.flags.push(f);
    rules.set(f.rule_id, bucket);
    const hours = resolutionHours(f);
    if (hours !== null) durations.push(hours);

    if (new Date(f.created_at).getTime() >= since) {
      const key = `${f.subject_type}|${f.subject_id}`;
      const row = subjects.get(key) ?? {
        subject_type: f.subject_type,
        subject_id: f.subject_id,
        count: 0,
        rules: [],
        lastAt: f.created_at,
      };
      row.count += 1;
      if (!row.rules.includes(f.rule_id)) row.rules.push(f.rule_id);
      if (f.created_at > row.lastAt) row.lastAt = f.created_at;
      subjects.set(key, row);
    }
  }

  const byRule: RuleRow[] = [...rules.entries()]
    .map(([rule, { flags: rows }]) => {
      const resolvedRows = rows.filter((f) => isResolved(f.status));
      const fp = resolvedRows.filter((f) => f.status === FALSE_POSITIVE_STATUS).length;
      const hours = resolvedRows
        .map((f) => resolutionHours(f))
        .filter((h): h is number => h !== null);
      return {
        rule,
        total: rows.length,
        open: rows.length - resolvedRows.length,
        resolved: resolvedRows.length,
        falsePositives: fp,
        avgResolutionHours: mean(hours),
        falsePositiveRate: resolvedRows.length ? fp / resolvedRows.length : null,
      };
    })
    .sort((a, b) => b.total - a.total || a.rule.localeCompare(b.rule));

  const resolvedAll = flags.filter((f) => isResolved(f.status));
  const fpAll = resolvedAll.filter((f) => f.status === FALSE_POSITIVE_STATUS).length;

  return {
    total: flags.length,
    open,
    resolved: resolvedAll.length,
    overdue,
    bySeverity,
    byRule,
    avgResolutionHours: mean(durations),
    medianResolutionHours: median(durations),
    falsePositiveRate: resolvedAll.length ? fpAll / resolvedAll.length : null,
    repeatSubjects: [...subjects.values()]
      .filter((s) => s.count >= repeatMin)
      .sort((a, b) => b.count - a.count || b.lastAt.localeCompare(a.lastAt))
      .slice(0, topSubjects),
  };
}
