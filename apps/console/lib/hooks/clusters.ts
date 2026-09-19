"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { clustersApi, type Cluster } from "../clusters";
import { useSession } from "../session-context";

/** Clusters the caller may see (any staff role; farmers never use the console). */
export function useClusters(enabled = true) {
  const { status, role } = useSession();
  return useQuery({
    queryKey: ["clusters"],
    queryFn: clustersApi.list,
    enabled: enabled && status === "authenticated" && role !== "farmer",
    staleTime: 5 * 60_000,
    select: (d) => d.items,
  });
}

/** Cluster id -> cluster. */
export function useClusterMap(enabled = true): Map<string, Cluster> {
  const q = useClusters(enabled);
  return React.useMemo(() => new Map((q.data ?? []).map((c) => [c.id, c])), [q.data]);
}
