/**
 * AN-011 dashboard filters (tenant from the token; date range, cluster, store, officer, crop).
 * Pure URL <-> filter mapping used by `useAnalyticsFilters()` (lib/hooks/use-analytics-filters.ts).
 * Acceptance "filters persist in URL": every filter lives in the query string, so reload,
 * back / forward and shared links keep them.
 *
 * URL keys: `from`, `to` (IST `YYYY-MM-DD`), `cluster`, `store`, `officer`, `crop`.
 * Defaults: the 30 days ending today (IST), matching the API default (docs/prs/M4-analytics-api.md).
 */
import type { AnalyticsApiFilters } from "./analytics";

export const FILTER_KEYS = ["from", "to", "cluster", "store", "officer", "crop"] as const;
export type FilterKey = (typeof FILTER_KEYS)[number];
export type EntityFilterKey = "cluster" | "store" | "officer" | "crop";

export interface AnalyticsFilters {
  from: string;
  to: string;
  cluster?: string;
  store?: string;
  officer?: string;
  crop?: string;
}

export type FilterPatch = Partial<Record<FilterKey, string | undefined>>;

export type FilterIssue =
  | "invalid_date"
  | "reversed_range"
  | "range_too_long"
  | "invalid_id"
  | "store_outside_cluster"
  | "officer_outside_scope";

export const DEFAULT_RANGE_DAYS = 30;
/** The API refuses longer ranges (422 `invalid_date_range`). */
export const MAX_RANGE_DAYS = 366;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
/** Ids are UUIDs in the API; the mock uses short slugs. Anything else is dropped. */
const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const DAY_MS = 86_400_000;
const IST_OFFSET_MS = 330 * 60_000;

/** Today's calendar day in IST. */
export function todayIst(now: Date = new Date()): string {
  return new Date(now.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}

export function isIsoDate(value: string | null | undefined): value is string {
  if (!value || !DATE_RE.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

export function addDays(day: string, days: number): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
}

/** Inclusive number of days in a range. */
export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS) + 1;
}

export function defaultRange(today: string = todayIst()): { from: string; to: string } {
  return { from: addDays(today, -(DEFAULT_RANGE_DAYS - 1)), to: today };
}

export interface ParsedFilters {
  filters: AnalyticsFilters;
  /** Problems found in the URL (the filters are already corrected). */
  issues: FilterIssue[];
  /** True when from/to are the default range (not in the URL or equal to it). */
  isDefaultRange: boolean;
}

type ParamSource = Pick<URLSearchParams, "get">;

/** URL -> filters. Malformed values are dropped, a reversed range swapped, a long range cut. */
export function parseFilters(params: ParamSource, today: string = todayIst()): ParsedFilters {
  const issues: FilterIssue[] = [];
  const def = defaultRange(today);
  const rawFrom = params.get("from");
  const rawTo = params.get("to");
  let from = def.from;
  let to = def.to;
  const fromOk = isIsoDate(rawFrom);
  const toOk = isIsoDate(rawTo);
  if ((rawFrom && !fromOk) || (rawTo && !toOk)) issues.push("invalid_date");
  if (fromOk && toOk) {
    from = rawFrom;
    to = rawTo;
  } else if (fromOk) {
    from = rawFrom;
    to = rawFrom > def.to ? rawFrom : def.to;
  } else if (toOk) {
    to = rawTo;
    from = addDays(rawTo, -(DEFAULT_RANGE_DAYS - 1));
  }
  if (from > to) {
    issues.push("reversed_range");
    [from, to] = [to, from];
  }
  if (daysBetween(from, to) > MAX_RANGE_DAYS) {
    issues.push("range_too_long");
    from = addDays(to, -(MAX_RANGE_DAYS - 1));
  }
  const filters: AnalyticsFilters = { from, to };
  for (const key of ["cluster", "store", "officer", "crop"] as const) {
    const v = params.get(key);
    if (!v) continue;
    if (ID_RE.test(v)) filters[key] = v;
    else if (!issues.includes("invalid_id")) issues.push("invalid_id");
  }
  return { filters, issues, isDefaultRange: from === def.from && to === def.to };
}

/**
 * Apply a change. Choosing a cluster clears a store and officer the user did not set in the
 * same patch (they may sit outside it: 422 `invalid_filter_combination`); choosing a store
 * clears the officer.
 */
export function applyFilterChange(prev: AnalyticsFilters, patch: FilterPatch): AnalyticsFilters {
  const next: AnalyticsFilters = { ...prev };
  for (const [k, v] of Object.entries(patch) as Array<[FilterKey, string | undefined]>) {
    if (k === "from" || k === "to") {
      if (v) next[k] = v;
    } else if (v) next[k] = v;
    else delete next[k];
  }
  const changed = (k: EntityFilterKey) => k in patch && patch[k] !== prev[k];
  if (changed("cluster")) {
    if (!("store" in patch)) delete next.store;
    if (!("officer" in patch)) delete next.officer;
  } else if (changed("store") && !("officer" in patch)) delete next.officer;
  if (next.from > next.to) [next.from, next.to] = [next.to, next.from];
  return next;
}

/**
 * Filters -> URL, keeping every other parameter (search, sort, tab, replay date). The date
 * range is written only when it differs from the default so plain links stay short.
 */
export function serializeFilters(
  filters: AnalyticsFilters,
  current: ParamSource & { toString(): string } = new URLSearchParams(),
  today: string = todayIst(),
): string {
  const out = new URLSearchParams(current.toString());
  for (const k of FILTER_KEYS) out.delete(k);
  const def = defaultRange(today);
  if (filters.from !== def.from || filters.to !== def.to) {
    out.set("from", filters.from);
    out.set("to", filters.to);
  }
  for (const k of ["cluster", "store", "officer", "crop"] as const) {
    const v = filters[k];
    if (v) out.set(k, v);
  }
  // Stable order: filters first, then the screen's own parameters.
  const ordered = new URLSearchParams();
  for (const k of FILTER_KEYS) {
    const v = out.get(k);
    if (v) ordered.set(k, v);
  }
  out.forEach((v, k) => {
    if (!(FILTER_KEYS as readonly string[]).includes(k)) ordered.append(k, v);
  });
  return ordered.toString();
}

/** Only the filter part of the URL (for links between dashboards). */
export function filterQueryString(filters: AnalyticsFilters, today: string = todayIst()): string {
  return serializeFilters(filters, new URLSearchParams(), today);
}

export function toApiFilters(f: AnalyticsFilters): AnalyticsApiFilters {
  return {
    from: f.from,
    to: f.to,
    ...(f.cluster ? { cluster_id: f.cluster } : {}),
    ...(f.store ? { store_id: f.store } : {}),
    ...(f.officer ? { officer_id: f.officer } : {}),
    ...(f.crop ? { crop_id: f.crop } : {}),
  };
}

export interface FilterMembership {
  /** store id -> cluster id */
  storeCluster: ReadonlyMap<string, string | null>;
  /** officer id -> { store, cluster } */
  officerPlacement: ReadonlyMap<string, { store: string | null; cluster: string | null }>;
}

/**
 * Drop a store outside the chosen cluster and an officer outside the chosen store / cluster
 * (known once the option lists load). Unknown ids are kept: the API answers 404 for them.
 */
export function reconcileFilters(
  f: AnalyticsFilters,
  m: FilterMembership,
): { filters: AnalyticsFilters; issues: FilterIssue[] } {
  const next = { ...f };
  const issues: FilterIssue[] = [];
  if (next.cluster && next.store && m.storeCluster.has(next.store)) {
    if (m.storeCluster.get(next.store) !== next.cluster) {
      delete next.store;
      issues.push("store_outside_cluster");
    }
  }
  if (next.officer && m.officerPlacement.has(next.officer)) {
    const p = m.officerPlacement.get(next.officer)!;
    if ((next.store && p.store !== next.store) || (next.cluster && p.cluster !== next.cluster)) {
      delete next.officer;
      issues.push("officer_outside_scope");
    }
  }
  return { filters: next, issues };
}
