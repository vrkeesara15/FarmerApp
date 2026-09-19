"use client";

/**
 * `useAnalyticsFilters()` — the AN-011 filter set bound to the URL (acceptance: filters
 * persist in the URL). Reads `from / to / cluster / store / officer / crop` from the search
 * params, writes them back with `router.push` (so back / forward step through filter changes;
 * pass `{ replace: true }` for corrections), keeps every other parameter of the page.
 * Pages using it must sit inside a <Suspense> boundary (Next's useSearchParams rule).
 */
import * as React from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import {
  applyFilterChange,
  defaultRange,
  filterQueryString,
  parseFilters,
  serializeFilters,
  toApiFilters,
  todayIst,
  type AnalyticsFilters,
  type FilterIssue,
  type FilterPatch,
} from "../analytics-filters";
import type { AnalyticsApiFilters } from "../analytics";

export interface NavigateOptions {
  replace?: boolean;
}

export interface UseAnalyticsFilters {
  filters: AnalyticsFilters;
  apiFilters: AnalyticsApiFilters;
  issues: FilterIssue[];
  isDefaultRange: boolean;
  /** Number of entity filters set (cluster, store, officer, crop) + 1 when the range is not the default. */
  activeCount: number;
  setFilters: (patch: FilterPatch, options?: NavigateOptions) => void;
  /** Back to the defaults (last 30 days, no entity filters); other parameters are kept. */
  reset: (options?: NavigateOptions) => void;
  /** `?from=…&store=…` for links to other dashboards (empty string when all default). */
  linkQuery: string;
}

function useNavigate() {
  const router = useRouter();
  const pathname = usePathname() ?? "/";
  return React.useCallback(
    (qs: string, options: NavigateOptions = {}) => {
      const url = qs ? `${pathname}?${qs}` : pathname;
      if (options.replace) router.replace(url, { scroll: false });
      else router.push(url, { scroll: false });
    },
    [router, pathname],
  );
}

export function useAnalyticsFilters(): UseAnalyticsFilters {
  const params = useSearchParams();
  const navigate = useNavigate();
  const search = params?.toString() ?? "";
  const today = todayIst();

  const parsed = React.useMemo(
    () => parseFilters(new URLSearchParams(search), today),
    [search, today],
  );

  const setFilters = React.useCallback(
    (patch: FilterPatch, options?: NavigateOptions) => {
      const next = applyFilterChange(parsed.filters, patch);
      navigate(serializeFilters(next, new URLSearchParams(search), today), options);
    },
    [parsed.filters, navigate, search, today],
  );

  const reset = React.useCallback(
    (options?: NavigateOptions) => {
      navigate(serializeFilters(defaultRange(today), new URLSearchParams(search), today), options);
    },
    [navigate, search, today],
  );

  const { filters } = parsed;
  const activeCount =
    (["cluster", "store", "officer", "crop"] as const).filter((k) => !!filters[k]).length +
    (parsed.isDefaultRange ? 0 : 1);

  return {
    filters,
    apiFilters: React.useMemo(() => toApiFilters(filters), [filters]),
    issues: parsed.issues,
    isDefaultRange: parsed.isDefaultRange,
    activeCount,
    setFilters,
    reset,
    linkQuery: React.useMemo(() => {
      const qs = filterQueryString(filters, today);
      return qs ? `?${qs}` : "";
    }, [filters, today]),
  };
}

/** One non-filter URL parameter (search text, sort, tab, replay date) as state. */
export function useSearchParam(
  key: string,
): [string | undefined, (value: string | undefined, options?: NavigateOptions) => void] {
  const params = useSearchParams();
  const navigate = useNavigate();
  const search = params?.toString() ?? "";
  const value = new URLSearchParams(search).get(key) ?? undefined;
  const set = React.useCallback(
    (next: string | undefined, options?: NavigateOptions) => {
      const qs = new URLSearchParams(search);
      if (next) qs.set(key, next);
      else qs.delete(key);
      navigate(qs.toString(), options);
    },
    [key, navigate, search],
  );
  return [value, set];
}

/** Several non-filter parameters at once (one history entry). */
export function useSetSearchParams(): (
  patch: Record<string, string | undefined>,
  options?: NavigateOptions,
) => void {
  const params = useSearchParams();
  const navigate = useNavigate();
  const search = params?.toString() ?? "";
  return React.useCallback(
    (patch, options) => {
      const qs = new URLSearchParams(search);
      for (const [k, v] of Object.entries(patch)) {
        if (v) qs.set(k, v);
        else qs.delete(k);
      }
      navigate(qs.toString(), options);
    },
    [navigate, search],
  );
}
