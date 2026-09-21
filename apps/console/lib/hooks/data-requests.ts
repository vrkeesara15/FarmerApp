"use client";

/**
 * TanStack Query hooks over lib/data-requests.ts (NF-013). Same shape as lib/hooks/admin.ts:
 * queries wait for the session, every write invalidates the queue, and the two step-up calls
 * take the runner from `useStepUp()` so a 401 `step_up_required` opens the OTP dialog and
 * retries with `X-Step-Up-Token`.
 */
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { dataRequestsApi, type DataRequestFilters, type DataRequestStatus } from "../data-requests";
import { useSession } from "../session-context";
import type { StepUpRunner } from "@/components/admin/StepUp";

export const dataRequestKeys = {
  all: ["data-requests"] as const,
  list: (f: DataRequestFilters) => ["data-requests", "list", f] as const,
};

export function useDataRequests(filters: DataRequestFilters, enabled = true) {
  const ready = useSession().status === "authenticated";
  return useQuery({
    queryKey: dataRequestKeys.list(filters),
    queryFn: () => dataRequestsApi.list({ ...filters, limit: 100 }),
    enabled: ready && enabled,
  });
}

function useQueueMutation<V, R>(fn: (vars: V) => Promise<R>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: dataRequestKeys.all }),
  });
}

export function useUpdateDataRequest() {
  return useQueueMutation(
    ({ id, status, note }: { id: string; status: DataRequestStatus; note?: string }) =>
      dataRequestsApi.update(id, { status, note }),
  );
}

export function useApplyCorrection(stepUp: StepUpRunner) {
  return useQueueMutation((id: string) =>
    stepUp.run((h) => dataRequestsApi.applyCorrection(id, h)),
  );
}

export function useRunErasure(stepUp: StepUpRunner) {
  return useQueueMutation((id: string) => stepUp.run((h) => dataRequestsApi.erase(id, h)));
}

/** The export is read-only: it never invalidates the queue. */
export function useExportData() {
  return useMutation({ mutationFn: (id: string) => dataRequestsApi.export(id) });
}
