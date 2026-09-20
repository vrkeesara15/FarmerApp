"use client";

/** TanStack Query hooks over lib/mlops.ts (AN-006 crop health, AN-007 quality, DX-012 releases). */
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { mlopsApi, type CropHealthFilters } from "../mlops";
import { useSession } from "../session-context";

export const mlopsKeys = {
  cropHealth: (f: CropHealthFilters) => ["crop-health", f] as const,
  quality: (days: number) => ["diagnosis-quality", days] as const,
  evaluations: () => ["diagnosis-evaluations"] as const,
  releases: (status?: string) => ["model-releases", status ?? "all"] as const,
  currentModel: () => ["model-current"] as const,
};

function useReady(): boolean {
  return useSession().status === "authenticated";
}

export function useCropHealth(filters: CropHealthFilters) {
  const ready = useReady();
  return useQuery({
    queryKey: mlopsKeys.cropHealth(filters),
    queryFn: () => mlopsApi.cropHealth(filters),
    enabled: ready,
    placeholderData: keepPreviousData,
  });
}

export function useDiagnosisQuality(days = 30) {
  const ready = useReady();
  return useQuery({
    queryKey: mlopsKeys.quality(days),
    queryFn: () => mlopsApi.quality(days),
    enabled: ready,
    placeholderData: keepPreviousData,
  });
}

export function useEvaluations(enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: mlopsKeys.evaluations(),
    queryFn: () => mlopsApi.evaluations(10),
    enabled: ready && enabled,
  });
}

export function useModelReleases(status?: string) {
  const ready = useReady();
  return useQuery({
    queryKey: mlopsKeys.releases(status),
    queryFn: () => mlopsApi.releases(status),
    enabled: ready,
  });
}

/** The approved on-device model; 404 `no_approved_model` simply means "none yet". */
export function useCurrentModel() {
  const ready = useReady();
  return useQuery({
    queryKey: mlopsKeys.currentModel(),
    queryFn: mlopsApi.currentModel,
    enabled: ready,
    retry: false,
  });
}

/** DX-012 approve / reject / retire — behind step-up (SEC-028) and audited. */
export function useDecideRelease() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      id,
      decision,
      note,
      headers,
    }: {
      id: string;
      decision: "approve" | "reject" | "retire";
      note: string | null;
      headers?: Record<string, string>;
    }) => mlopsApi.decide(id, { decision, note }, headers ?? {}),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["model-releases"] });
      void qc.invalidateQueries({ queryKey: mlopsKeys.currentModel() });
    },
  });
}
