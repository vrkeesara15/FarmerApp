"use client";

/**
 * TanStack Query hooks over lib/admin.ts (WC-011, WC-012, WC-103). Mutations that need step-up
 * take the runner from `useStepUp()` (components/admin/StepUp.tsx) so a 401 `step_up_required`
 * opens the OTP dialog and retries. Queries wait for the session.
 */
import * as React from "react";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  USER_READ_ROLES,
  adminApi,
  patchNeedsStepUp,
  type AdminUser,
  type AuditFilters,
  type SettingsPatch,
  type UserCreateBody,
  type UserUpdateBody,
} from "../admin";
import { useSession } from "../session-context";
import type { StepUpRunner } from "@/components/admin/StepUp";

export const adminKeys = {
  all: ["admin"] as const,
  users: () => ["admin", "users"] as const,
  user: (id: string) => ["admin", "user", id] as const,
  devices: (id: string) => ["admin", "devices", id] as const,
  settings: () => ["admin", "settings"] as const,
  audit: (f: AuditFilters) => ["admin", "audit", f] as const,
};

function useReady(): boolean {
  return useSession().status === "authenticated";
}

/** Every user the caller may see (follows `next_cursor` to the end; tenants have < 1,000 staff). */
async function allUsers(): Promise<AdminUser[]> {
  const out: AdminUser[] = [];
  let cursor: string | null | undefined = null;
  for (let i = 0; i < 20; i++) {
    const page = await adminApi.users(cursor, 200);
    out.push(...page.items);
    cursor = page.next_cursor;
    if (!cursor) break;
  }
  return out;
}

export function useUsers(enabled = true) {
  const ready = useReady();
  return useQuery({ queryKey: adminKeys.users(), queryFn: allUsers, enabled: ready && enabled });
}

/** id -> name for owners, watchers, actors; empty for roles that cannot list users. */
export function useUserNames(): Map<string, AdminUser> {
  const { role } = useSession();
  const users = useUsers(!!role && USER_READ_ROLES.includes(role));
  return React.useMemo(() => new Map((users.data ?? []).map((u) => [u.id, u])), [users.data]);
}

export function useUser(id: string) {
  const ready = useReady();
  return useQuery({
    queryKey: adminKeys.user(id),
    queryFn: () => adminApi.user(id),
    enabled: ready && !!id,
  });
}

export function useDevices(userId: string) {
  const ready = useReady();
  return useQuery({
    queryKey: adminKeys.devices(userId),
    queryFn: () => adminApi.devices(userId),
    enabled: ready && !!userId,
  });
}

function useAdminMutation<V, R>(fn: (vars: V) => Promise<R>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: adminKeys.all }),
  });
}

export function useCreateUser(stepUp: StepUpRunner) {
  return useAdminMutation((body: UserCreateBody) =>
    stepUp.run((h) => adminApi.createUser(body, h)),
  );
}

export function useUpdateUser(stepUp: StepUpRunner) {
  return useAdminMutation(({ id, body }: { id: string; body: UserUpdateBody }) =>
    patchNeedsStepUp(body)
      ? stepUp.run((h) => adminApi.updateUser(id, body, h))
      : adminApi.updateUser(id, body, {}),
  );
}

export function useDeactivateUser(stepUp: StepUpRunner) {
  return useAdminMutation((id: string) => stepUp.run((h) => adminApi.deactivate(id, h)));
}

export function useForceLogout(stepUp: StepUpRunner) {
  return useAdminMutation((id: string) => stepUp.run((h) => adminApi.forceLogout(id, h)));
}

export function useBindDevice(stepUp: StepUpRunner) {
  return useAdminMutation(({ userId, deviceId }: { userId: string; deviceId: string }) =>
    stepUp.run((h) => adminApi.bindDevice(userId, deviceId, h)),
  );
}

export function useReportLost(stepUp: StepUpRunner) {
  return useAdminMutation(({ userId, deviceId }: { userId: string; deviceId: string }) =>
    stepUp.run((h) => adminApi.reportLost(userId, deviceId, h)),
  );
}

export function useSettings(enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: adminKeys.settings(),
    queryFn: adminApi.settings,
    enabled: ready && enabled,
  });
}

export function useUpdateSettings(stepUp: StepUpRunner) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (patch: SettingsPatch) => stepUp.run((h) => adminApi.updateSettings(patch, h)),
    onSuccess: (settings) => {
      qc.setQueryData(adminKeys.settings(), settings);
      void qc.invalidateQueries({ queryKey: ["admin", "audit"] });
    },
  });
}

export function useAuditLogs(filters: AuditFilters, enabled = true) {
  const ready = useReady();
  return useInfiniteQuery({
    queryKey: adminKeys.audit(filters),
    queryFn: ({ pageParam }) => adminApi.auditLogs({ ...filters, cursor: pageParam, limit: 50 }),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    enabled: ready && enabled,
  });
}
