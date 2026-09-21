"use client";

/**
 * TanStack Query hooks over lib/analytics.ts (M4 dashboards). Every query waits for the
 * session, is keyed by the AN-011 filters, and keeps the previous data while a filter change
 * loads (no flash of empty content). Filter option lists load in parallel with the data.
 */
import * as React from "react";
import {
  keepPreviousData,
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import {
  analytics,
  type AnalyticsApiFilters,
  type FarmerDirectoryQuery,
  type ScorecardRow,
  type SegmentDefinition,
  type StoreRow,
} from "../analytics";
import { catalog, type Crop } from "../catalog";
import { addDays, defaultRange } from "../analytics-filters";
import { FIELD_TEAM_ROLES, STORE_ROLES } from "../nav";
import { useClusters } from "./clusters";
import { useSession } from "../session-context";

export const analyticsKeys = {
  all: ["analytics"] as const,
  ownerHome: (f: AnalyticsApiFilters) => ["analytics", "owner-home", f] as const,
  fieldTeam: (f: AnalyticsApiFilters) => ["analytics", "field-team", f] as const,
  officer: (id: string, f: AnalyticsApiFilters) => ["analytics", "officer", id, f] as const,
  replay: (id: string, date: string, f: AnalyticsApiFilters) =>
    ["analytics", "replay", id, date, f] as const,
  farmers: (f: AnalyticsApiFilters, q: FarmerDirectoryQuery) =>
    ["analytics", "farmers", f, q] as const,
  farmer360: (id: string, f: AnalyticsApiFilters) => ["analytics", "farmer360", id, f] as const,
  stores: (f: AnalyticsApiFilters) => ["analytics", "stores", f] as const,
  store: (id: string, f: AnalyticsApiFilters) => ["analytics", "store", id, f] as const,
  segments: () => ["analytics", "segments"] as const,
  segmentPreview: (f: AnalyticsApiFilters, d: SegmentDefinition) =>
    ["analytics", "segment-preview", f, d] as const,
  churnRisk: (f: AnalyticsApiFilters, days: number) =>
    ["analytics", "churn-risk", f, days] as const,
};

function useReady(): boolean {
  return useSession().status === "authenticated";
}

const hasRole = (role: string | undefined, roles: readonly string[]) =>
  !!role && roles.includes(role);

export function useOwnerHome(f: AnalyticsApiFilters) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.ownerHome(f),
    queryFn: () => analytics.ownerHome(f),
    enabled: ready,
    placeholderData: keepPreviousData,
  });
}

export function useFieldTeam(f: AnalyticsApiFilters) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.fieldTeam(f),
    queryFn: () => analytics.fieldTeam(f),
    enabled: ready,
    placeholderData: keepPreviousData,
  });
}

export function useOfficer(id: string, f: AnalyticsApiFilters) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.officer(id, f),
    queryFn: () => analytics.officer(id, f),
    enabled: ready && !!id,
    placeholderData: keepPreviousData,
  });
}

export function useDayReplay(
  id: string,
  date: string | undefined,
  f: AnalyticsApiFilters,
  enabled = true,
) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.replay(id, date ?? "", f),
    queryFn: () => analytics.dayReplay(id, date ?? "", f),
    enabled: ready && enabled && !!id && !!date,
  });
}

export function useFarmerDirectory(f: AnalyticsApiFilters, q: FarmerDirectoryQuery) {
  const ready = useReady();
  return useInfiniteQuery({
    queryKey: analyticsKeys.farmers(f, q),
    queryFn: ({ pageParam }) => analytics.farmers(f, { ...q, cursor: pageParam ?? undefined }),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last.next_cursor,
    enabled: ready,
    placeholderData: keepPreviousData,
  });
}

export function useFarmer360(id: string, f: AnalyticsApiFilters) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.farmer360(id, f),
    queryFn: () => analytics.farmer360(id, f),
    enabled: ready && !!id,
  });
}

export function useStoresAnalytics(f: AnalyticsApiFilters, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.stores(f),
    queryFn: () => analytics.stores(f),
    enabled: ready && enabled,
    placeholderData: keepPreviousData,
  });
}

export function useStoreDetail(id: string, f: AnalyticsApiFilters) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.store(id, f),
    queryFn: () => analytics.store(id, f),
    enabled: ready && !!id,
    placeholderData: keepPreviousData,
  });
}

// ---- AN-004 segments -------------------------------------------------------------------------
/** C32: what a definition selects right now. Disabled while the builder is empty. */
export function useSegmentPreview(
  f: AnalyticsApiFilters,
  definition: SegmentDefinition,
  enabled = true,
) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.segmentPreview(f, definition),
    queryFn: () => analytics.segmentPreview(f, definition),
    enabled: ready && enabled,
    placeholderData: keepPreviousData,
  });
}

export function useSavedSegments(enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.segments(),
    queryFn: analytics.savedSegments,
    enabled: ready && enabled,
  });
}

/** Create, rename / redefine or delete a saved segment; the list refetches after each. */
export function useSaveSegment(f: AnalyticsApiFilters) {
  const qc = useQueryClient();
  const done = () => void qc.invalidateQueries({ queryKey: analyticsKeys.segments() });
  const create = useMutation({
    mutationFn: (body: {
      name: string;
      description: string | null;
      definition: SegmentDefinition;
    }) => analytics.createSegment(f, body),
    onSuccess: done,
  });
  const update = useMutation({
    mutationFn: ({
      id,
      ...body
    }: {
      id: string;
      name?: string;
      description?: string | null;
      definition?: SegmentDefinition;
    }) => analytics.updateSegment(id, f, body),
    onSuccess: done,
  });
  const remove = useMutation({
    mutationFn: (id: string) => analytics.deleteSegment(id),
    onSuccess: done,
  });
  return { create, update, remove };
}

/** AN-004 churn-risk list (prior customers with no purchase or visit in `days`). */
export function useChurnRisk(f: AnalyticsApiFilters, days: number, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: analyticsKeys.churnRisk(f, days),
    queryFn: () => analytics.churnRisk(f, { days, limit: 50 }),
    enabled: ready && enabled,
    placeholderData: keepPreviousData,
  });
}

/** First day of the month eleven months before `to`'s month: a 12-month P&L window. */
export function pnlWindow(to: string): { from: string; to: string } {
  const [y, m] = to.split("-").map(Number) as [number, number];
  const idx = y * 12 + (m - 1) - 11;
  const from = `${Math.floor(idx / 12)}-${String((idx % 12) + 1).padStart(2, "0")}-01`;
  return { from, to };
}

/** C41 "Store P&L view by month": the 12 months ending at the filter's `to`. */
export function useStorePnl(id: string, f: AnalyticsApiFilters) {
  const window = pnlWindow(f.to);
  const pf: AnalyticsApiFilters = { ...f, ...window };
  return useStoreDetail(id, pf);
}

// ---- filter options ------------------------------------------------------------------------
export interface FilterOptionSets {
  stores: StoreRow[];
  officers: ScorecardRow[];
  crops: Crop[];
  /** Clusters with names from `GET /v1/clusters` and their store count. */
  clusters: Array<{ id: string; name: string; storeCount: number }>;
  storeName: (id: string | null | undefined) => string | undefined;
  officerName: (id: string | null | undefined) => string | undefined;
  loading: boolean;
}

/**
 * Stores from `/v1/analytics/stores`, clusters from `/v1/clusters`, officers from `/v1/analytics/field-team`,
 * crops from `/v1/catalog/crops`, each over the default range and only for roles that may read
 * them; cached for 5 minutes and fetched in parallel with the page's own data.
 */
export function useFilterOptions(): FilterOptionSets {
  const { role, status } = useSession();
  const ready = status === "authenticated";
  const range = React.useMemo(() => {
    const d = defaultRange();
    return { from: addDays(d.to, -89), to: d.to };
  }, []);
  const stores = useQuery({
    queryKey: ["analytics", "options", "stores", range],
    queryFn: () => analytics.stores(range),
    enabled: ready && hasRole(role, STORE_ROLES),
    staleTime: 5 * 60_000,
  });
  const officers = useQuery({
    queryKey: ["analytics", "options", "officers", range],
    queryFn: () => analytics.fieldTeam(range),
    enabled: ready && hasRole(role, FIELD_TEAM_ROLES) && role !== "field_officer",
    staleTime: 5 * 60_000,
  });
  const clusters = useClusters(hasRole(role, STORE_ROLES));
  const crops = useQuery({
    queryKey: ["catalog", "crops"],
    queryFn: catalog.crops,
    enabled: ready,
    staleTime: 5 * 60_000,
  });
  return React.useMemo(() => {
    const storeList = stores.data?.items ?? [];
    const officerList = [...(officers.data?.items ?? [])].sort((a, b) =>
      a.name.localeCompare(b.name),
    );
    // Only clusters with a store in the analytics scope (a store count from that list).
    const storesPerCluster = new Map<string, number>();
    for (const s of storeList)
      if (s.cluster_id)
        storesPerCluster.set(s.cluster_id, (storesPerCluster.get(s.cluster_id) ?? 0) + 1);
    const storeNames = new Map(storeList.map((s) => [s.id, s.name]));
    const officerNames = new Map(officerList.map((o) => [o.officer_id, o.name]));
    return {
      stores: storeList,
      officers: officerList,
      crops: (crops.data ?? []).filter((c) => c.active),
      clusters: (clusters.data ?? [])
        .filter((c) => storesPerCluster.has(c.id))
        .map((c) => ({ id: c.id, name: c.name, storeCount: storesPerCluster.get(c.id)! })),
      storeName: (id) => (id ? storeNames.get(id) : undefined),
      officerName: (id) => (id ? officerNames.get(id) : undefined),
      loading: stores.isLoading || officers.isLoading || crops.isLoading || clusters.isLoading,
    };
  }, [
    stores.data,
    clusters.data,
    clusters.isLoading,
    officers.data,
    crops.data,
    stores.isLoading,
    officers.isLoading,
    crops.isLoading,
  ]);
}
