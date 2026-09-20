"use client";

/**
 * TanStack Query hooks over lib/campaigns.ts, lib/incentives.ts, lib/travel.ts and
 * lib/exports.ts (WC-008, WC-009, WC-013, AN-008). Queries wait for the session; mutations
 * invalidate the lists they change. Calls behind SEC-028 step-up take the headers from
 * `useStepUp().run(...)` — the hooks pass them straight through.
 */
import {
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
  keepPreviousData,
} from "@tanstack/react-query";
import {
  campaignsApi,
  type CampaignInput,
  type CampaignSegment,
  type CampaignStatus,
} from "../campaigns";
import { exportsApi, type ExportFormat, type ScheduleInput } from "../exports";
import {
  incentivesApi,
  type RuleDefinition,
  type TargetPatch,
  type TargetSubject,
} from "../incentives";
import { travelApi } from "../travel";
import { useSession } from "../session-context";

type Headers = Record<string, string>;

export const growthKeys = {
  campaigns: (status?: string) => ["campaigns", "list", status ?? "all"] as const,
  campaign: (id: string) => ["campaigns", "detail", id] as const,
  recipients: (id: string, status?: string) =>
    ["campaigns", "recipients", id, status ?? "all"] as const,
  roi: (id: string) => ["campaigns", "roi", id] as const,
  segmentCount: (segment: CampaignSegment) => ["campaigns", "segment-count", segment] as const,
  targets: (month: string, subject?: string) => ["targets", month, subject ?? "all"] as const,
  rules: () => ["incentive-rules"] as const,
  preview: (month: string, officer?: string, ruleSet?: string) =>
    ["incentives", "preview", month, officer ?? "me", ruleSet ?? "active"] as const,
  payouts: (month: string) => ["incentives", "payouts", month] as const,
  claims: (status?: string, officer?: string) =>
    ["travel", "claims", status ?? "all", officer ?? "all"] as const,
  statement: (month: string, officer: string) => ["travel", "statement", month, officer] as const,
  exportResources: () => ["exports", "resources"] as const,
  exports: () => ["exports", "list"] as const,
  schedules: () => ["report-schedules"] as const,
};

function useReady(): boolean {
  return useSession().status === "authenticated";
}

// ---- C80-C82 campaigns ---------------------------------------------------------------------

export function useCampaigns(status?: CampaignStatus | "") {
  const ready = useReady();
  return useInfiniteQuery({
    queryKey: growthKeys.campaigns(status || undefined),
    queryFn: ({ pageParam }) =>
      campaignsApi.list({ status: status || undefined, cursor: pageParam }),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    enabled: ready,
  });
}

export function useCampaign(id: string, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.campaign(id),
    queryFn: () => campaignsApi.get(id),
    enabled: ready && enabled && !!id,
  });
}

export function useCampaignRoi(id: string, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.roi(id),
    queryFn: () => campaignsApi.roi(id),
    enabled: ready && enabled && !!id,
  });
}

export function useCampaignRecipients(id: string, status: string | undefined, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.recipients(id, status),
    queryFn: () => campaignsApi.recipients(id, { status }),
    enabled: ready && enabled && !!id,
    placeholderData: keepPreviousData,
  });
}

/**
 * Live consented count while the segment is edited. `enabled` is false for an empty segment
 * (the API would count the whole tenant); the builder shows the "pick a criterion" copy then.
 */
export function useSegmentCount(segment: CampaignSegment, enabled: boolean) {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.segmentCount(segment),
    queryFn: () => campaignsApi.segmentCount(segment),
    enabled: ready && enabled,
    placeholderData: keepPreviousData,
    staleTime: 10_000,
  });
}

function useCampaignMutation<V, R>(fn: (vars: V) => Promise<R>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: ["campaigns"] }),
  });
}

export const useCreateCampaign = () =>
  useCampaignMutation((body: CampaignInput) => campaignsApi.create(body));
export const useUpdateCampaign = () =>
  useCampaignMutation(({ id, body }: { id: string; body: Partial<CampaignInput> }) =>
    campaignsApi.patch(id, body),
  );
export const useScheduleCampaign = () =>
  useCampaignMutation(({ id, sendAt }: { id: string; sendAt: string | null }) =>
    campaignsApi.schedule(id, sendAt),
  );
export const useCancelCampaign = () => useCampaignMutation((id: string) => campaignsApi.cancel(id));

// ---- C90 targets and incentives --------------------------------------------------------------

export function useTargets(month: string, subjectType?: TargetSubject) {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.targets(month, subjectType),
    queryFn: () => incentivesApi.targets(month, subjectType),
    enabled: ready && !!month,
    placeholderData: keepPreviousData,
  });
}

export function useSaveTargets() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      month,
      items,
      headers,
    }: {
      month: string;
      items: TargetPatch[];
      headers?: Headers;
    }) => incentivesApi.putTargets(month, items, headers ?? {}),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["targets"] }),
  });
}

export function useIncentiveRules() {
  const ready = useReady();
  return useQuery({ queryKey: growthKeys.rules(), queryFn: incentivesApi.rules, enabled: ready });
}

export function usePublishRules() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      name,
      definition,
      activate,
      headers,
    }: {
      name: string;
      definition: RuleDefinition;
      activate: boolean;
      headers?: Headers;
    }) => incentivesApi.createRule({ name, definition, activate }, headers ?? {}),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: growthKeys.rules() });
      void qc.invalidateQueries({ queryKey: ["incentives"] });
    },
  });
}

export function useActivateRules() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, headers }: { id: string; headers?: Headers }) =>
      incentivesApi.activateRule(id, headers ?? {}),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: growthKeys.rules() });
      void qc.invalidateQueries({ queryKey: ["incentives"] });
    },
  });
}

/** Payout preview for one officer and month; `definition` previews the unsaved editor draft. */
export function useIncentivePreview(
  params: { month: string; officer_id?: string; rule_set_id?: string },
  enabled = true,
) {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.preview(params.month, params.officer_id, params.rule_set_id),
    queryFn: () => incentivesApi.preview(params),
    enabled: ready && enabled && !!params.month,
    placeholderData: keepPreviousData,
  });
}

export function usePreviewDefinition() {
  return useMutation({
    mutationFn: (body: { officer_id: string; month: string; definition: RuleDefinition }) =>
      incentivesApi.previewDefinition(body),
  });
}

export function usePayouts(month: string, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.payouts(month),
    queryFn: () => incentivesApi.payouts(month),
    enabled: ready && enabled && !!month,
  });
}

export function useCloseIncentives() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ month, headers }: { month: string; headers?: Headers }) =>
      incentivesApi.close(month, headers ?? {}),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["incentives"] }),
  });
}

// ---- C91 travel allowance ---------------------------------------------------------------------

export function useTravelClaims(filters: { status?: string; officer_id?: string }) {
  const ready = useReady();
  return useInfiniteQuery({
    queryKey: growthKeys.claims(filters.status, filters.officer_id),
    queryFn: ({ pageParam }) => travelApi.claims({ ...filters, cursor: pageParam }),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    enabled: ready,
  });
}

export function useTravelStatement(month: string, officerId: string | undefined) {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.statement(month, officerId ?? ""),
    queryFn: () => travelApi.statement(month, officerId!),
    enabled: ready && !!month && !!officerId,
  });
}

export function useDecideClaim() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      id,
      decision,
      note,
    }: {
      id: string;
      decision: "approve" | "reject";
      note: string | null;
    }) => (decision === "approve" ? travelApi.approve(id, note) : travelApi.reject(id, note)),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["travel"] }),
  });
}

// ---- C100 exports and scheduled reports ------------------------------------------------------

export function useExportResources() {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.exportResources(),
    queryFn: exportsApi.resources,
    enabled: ready,
    staleTime: 5 * 60_000,
  });
}

export function useExportJobs() {
  const ready = useReady();
  return useQuery({ queryKey: growthKeys.exports(), queryFn: exportsApi.list, enabled: ready });
}

export function useRunExport() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      resource,
      filters,
      format,
      headers,
    }: {
      resource: string;
      filters: Record<string, unknown>;
      format: ExportFormat;
      headers?: Headers;
    }) => exportsApi.run({ resource, filters, format }, headers ?? {}),
    onSuccess: () => qc.invalidateQueries({ queryKey: growthKeys.exports() }),
  });
}

export function useReportSchedules() {
  const ready = useReady();
  return useQuery({
    queryKey: growthKeys.schedules(),
    queryFn: exportsApi.schedules,
    enabled: ready,
  });
}

function useScheduleMutation<V, R>(fn: (vars: V) => Promise<R>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: growthKeys.schedules() }),
  });
}

export const useCreateSchedule = () =>
  useScheduleMutation(({ body, headers }: { body: ScheduleInput; headers?: Headers }) =>
    exportsApi.createSchedule(body, headers ?? {}),
  );
export const useUpdateSchedule = () =>
  useScheduleMutation(
    ({ id, body, headers }: { id: string; body: Partial<ScheduleInput>; headers?: Headers }) =>
      exportsApi.patchSchedule(id, body, headers ?? {}),
  );
export const useDeleteSchedule = () =>
  useScheduleMutation(({ id, headers }: { id: string; headers?: Headers }) =>
    exportsApi.deleteSchedule(id, headers ?? {}),
  );
