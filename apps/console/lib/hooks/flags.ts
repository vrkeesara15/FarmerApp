"use client";

/** TanStack Query hooks over lib/flags.ts (WC-010). Queries wait for the session. */
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { flagsApi, type FlagFilters, type FlagStatus } from "../flags";
import { useSession } from "../session-context";

export const flagKeys = {
  all: ["flags"] as const,
  list: (f: FlagFilters) => ["flags", "list", f] as const,
  detail: (id: string) => ["flags", "detail", id] as const,
  summary: (days: number) => ["flags", "summary", days] as const,
};

function useReady(): boolean {
  return useSession().status === "authenticated";
}

/** Inbox pages (cursor pagination); counts come from the first page (whole filtered set). */
export function useFlagInbox(filters: FlagFilters, enabled = true) {
  const ready = useReady();
  return useInfiniteQuery({
    queryKey: flagKeys.list(filters),
    queryFn: ({ pageParam }) => flagsApi.list({ ...filters, cursor: pageParam }),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    enabled: ready && enabled,
  });
}

/** AN-009 data quality summary over the flags raised in the last `days` IST days. */
export function useFlagSummary(days: number, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: flagKeys.summary(days),
    queryFn: () => flagsApi.summary(days),
    enabled: ready && enabled,
  });
}

export function useFlag(id: string, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: flagKeys.detail(id),
    queryFn: () => flagsApi.get(id),
    enabled: ready && enabled && !!id,
  });
}

export function useTransitionFlag(id: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ to, note }: { to: FlagStatus; note: string | null }) =>
      flagsApi.transition(id, to, note),
    onSuccess: (detail) => {
      qc.setQueryData(flagKeys.detail(id), detail);
      void qc.invalidateQueries({ queryKey: ["flags", "list"] });
    },
  });
}

export function useCommentFlag(id: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: string) => flagsApi.comment(id, body),
    onSuccess: () => qc.invalidateQueries({ queryKey: flagKeys.detail(id) }),
  });
}

export function useAssignFlag(id: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ userId, note }: { userId: string; note: string | null }) =>
      flagsApi.assign(id, userId, note),
    onSuccess: (detail) => {
      qc.setQueryData(flagKeys.detail(id), detail);
      void qc.invalidateQueries({ queryKey: ["flags", "list"] });
    },
  });
}
