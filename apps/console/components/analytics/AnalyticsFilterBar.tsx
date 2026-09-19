"use client";

/**
 * FilterBar bound to `useAnalyticsFilters()` (AN-011). Options come from `useFilterOptions()`;
 * the store list narrows to the chosen cluster and the officer list to the chosen store /
 * cluster. Filters a role cannot change are hidden (the API narrows them to the role's scope).
 * Invalid values in a shared link are corrected in place (URL replaced) with a notice.
 */
import * as React from "react";
import { FilterBar, type FilterValues } from "@/components/ds/FilterBar";
import { reconcileFilters, type FilterPatch } from "@/lib/analytics-filters";
import { useFilterOptions } from "@/lib/hooks/analytics";
import type { UseAnalyticsFilters } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";
import { filterVisibility } from "@/lib/nav";
import { useSession } from "@/lib/session-context";

export interface AnalyticsFilterBarProps {
  state: UseAnalyticsFilters;
  onExport?: () => void;
  exporting?: boolean;
  /** Hide filters that do not apply to a screen. */
  hide?: Partial<Record<"cluster" | "store" | "officer" | "crop" | "date", boolean>>;
}

export function AnalyticsFilterBar({ state, onExport, exporting, hide }: AnalyticsFilterBarProps) {
  const t = useT();
  const { role } = useSession();
  const opts = useFilterOptions();
  const { filters, setFilters, reset, issues } = state;
  const [corrected, setCorrected] = React.useState(false);

  // Malformed / reversed / too long values from the URL: rewrite the corrected set.
  React.useEffect(() => {
    if (issues.length === 0) return;
    setCorrected(true);
    setFilters({}, { replace: true });
  }, [issues, setFilters]);

  // Store outside the cluster / officer outside the store, once the option lists are known.
  React.useEffect(() => {
    if (opts.loading || (opts.stores.length === 0 && opts.officers.length === 0)) return;
    const { filters: next, issues: found } = reconcileFilters(filters, {
      storeCluster: new Map(opts.stores.map((s) => [s.id, s.cluster_id])),
      officerPlacement: new Map(
        opts.officers.map((o) => [o.officer_id, { store: o.store_id, cluster: o.cluster_id }]),
      ),
    });
    if (found.length === 0) return;
    setCorrected(true);
    setFilters({ store: next.store, officer: next.officer }, { replace: true });
  }, [filters, opts.loading, opts.stores, opts.officers, setFilters]);

  const vis = filterVisibility(role);
  const show = {
    cluster: vis.cluster && !hide?.cluster && opts.clusters.length > 1,
    store: vis.store && !hide?.store,
    officer: vis.officer && !hide?.officer,
    crop: !hide?.crop,
    date: !hide?.date,
  };

  const value: FilterValues = {
    cluster: filters.cluster,
    store: filters.store,
    officer: filters.officer,
    crop: filters.crop,
    date: { start: filters.from, end: filters.to },
  };

  const onChange = (next: FilterValues) => {
    if (Object.keys(next).length === 0) {
      reset();
      return;
    }
    const patch: FilterPatch = {};
    for (const k of ["cluster", "store", "officer", "crop"] as const)
      if (next[k] !== filters[k]) patch[k] = next[k];
    if (next.date?.start && next.date.start !== filters.from) patch.from = next.date.start;
    if (next.date?.end && next.date.end !== filters.to) patch.to = next.date.end;
    if (next.date && next.date.start && next.date.end && next.date.start > next.date.end) return;
    if (Object.keys(patch).length) setFilters(patch);
  };

  const stores = opts.stores.filter((s) => !filters.cluster || s.cluster_id === filters.cluster);
  const officers = opts.officers.filter(
    (o) =>
      (!filters.store || o.store_id === filters.store) &&
      (!filters.cluster || o.cluster_id === filters.cluster),
  );

  return (
    <div className="flex flex-col gap-2">
      <FilterBar
        value={value}
        onChange={onChange}
        show={show}
        onExport={onExport}
        exporting={exporting}
        options={{
          clusters: opts.clusters.map((c) => ({
            value: c.id,
            label: t("analytics.clusterOption", {
              name: [...new Set(c.districts)][0] ?? c.id,
              n: c.districts.length,
            }),
          })),
          stores: stores.map((s) => ({ value: s.id, label: s.name })),
          officers: officers.map((o) => ({ value: o.officer_id, label: o.name })),
          crops: opts.crops.map((c) => ({ value: c.id, label: c.name })),
        }}
      />
      {corrected ? (
        <p role="status" className="text-small text-warning" data-testid="filters-corrected">
          {t("analytics.filtersCorrected")}
        </p>
      ) : null}
    </div>
  );
}
