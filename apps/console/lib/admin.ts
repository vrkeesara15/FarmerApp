/**
 * Administration API (WC-011 users and devices, WC-012 settings, WC-103 audit log). Shapes
 * mirror apps/api/openapi.yaml (`UserOut`, `UserCreate`, `UserUpdate`, `DeviceOut`,
 * `ForceLogoutOut`, `TenantSettings`, `SettingsPatch`, `AuditLogOut`). Calls marked
 * `x-step-up: true` take the step-up headers from `runWithStepUp` (lib/step-up.ts).
 */
import { ApiError, authedFetch, getAuthToken, session, API_BASE_URL, type UserRole } from "./api";

type Headers = Record<string, string>;

// ---- roles (x-roles in openapi.yaml) -------------------------------------------------------
export const USER_READ_ROLES: ReadonlyArray<string> = [
  "owner",
  "director",
  "tenant_admin",
  "cluster_head",
  "auditor",
];
export const USER_WRITE_ROLES: ReadonlyArray<string> = ["owner", "director", "tenant_admin"];
export const SETTINGS_ROLES: ReadonlyArray<string> = ["owner", "director", "tenant_admin"];
export const AUDIT_ROLES: ReadonlyArray<string> = ["owner", "director", "auditor", "tenant_admin"];

/** Staff roles an admin can assign (farmers sign up through /v1/farmers). */
export const STAFF_ROLES = [
  "owner",
  "director",
  "cluster_head",
  "auditor",
  "store_manager",
  "accountant",
  "field_officer",
  "agronomist",
  "tenant_admin",
] as const satisfies ReadonlyArray<UserRole>;

export const LANGUAGES = ["en", "te", "kn", "hi", "mr"] as const;
export type Language = (typeof LANGUAGES)[number];

// ---- users and devices -----------------------------------------------------------------------
export interface AdminUser {
  id: string;
  tenant_id: string;
  phone: string;
  name: string;
  role: string;
  store_id: string | null;
  cluster_id: string | null;
  language: string;
  status: "active" | "disabled" | string;
  created_at: string;
}

export interface UserPage {
  items: AdminUser[];
  next_cursor?: string | null;
}

export interface UserCreateBody {
  phone: string;
  name: string;
  role: string;
  store_id?: string | null;
  cluster_id?: string | null;
  language?: Language | null;
}

export interface UserUpdateBody {
  name?: string;
  role?: string;
  status?: "active" | "disabled";
  store_id?: string | null;
  cluster_id?: string | null;
}

export type DeviceStatus = "pending" | "active" | "revoked" | "lost";

export interface Device {
  id: string;
  user_id: string;
  device_id: string;
  platform: string | null;
  model: string | null;
  app_version: string | null;
  first_seen: string;
  last_seen: string;
  status: DeviceStatus;
  bound_at: string | null;
  revoked_at: string | null;
}

export interface ForceLogoutResult {
  user_id: string;
  revoked_sessions: number;
  tokens_valid_after: string;
}

/** Role / status changes need step-up (PATCH /v1/users/{id}); name and assignment do not. */
export function patchNeedsStepUp(body: UserUpdateBody): boolean {
  return body.role !== undefined || body.status !== undefined;
}

/** Summary of a user's devices for the users table. */
export function deviceSummary(devices: ReadonlyArray<Device>): DeviceStatus | "none" {
  if (devices.some((d) => d.status === "pending")) return "pending";
  if (devices.some((d) => d.status === "active")) return "active";
  if (devices.some((d) => d.status === "lost")) return "lost";
  if (devices.length) return "revoked";
  return "none";
}

// ---- settings --------------------------------------------------------------------------------
export interface Sampling {
  moving_s: number;
  stationary_s: number;
  upload_s: number;
}

export interface Branding {
  app_name_agent: string | null;
  app_name_farmer: string | null;
  primary_colour: string;
  logo_blob_uri: string | null;
  support_phone: string | null;
}

export interface TenantSettings {
  consent_version: string;
  geofence_radius_m: number;
  meeting_point_radius_m: number | null;
  min_visit_duration_s: number;
  auto_duty_end_local_time: string;
  idle_end_minutes: number;
  location_policy_version: string;
  sampling: Sampling;
  ta_rate_per_km_paise: number;
  store_manager_max_credit_limit_paise: number;
  credit_due_days: number;
  day_close_variance_threshold_paise: number;
  webhook_replay_window_s: number;
  legal_name: string | null;
  gstin_by_state: Record<string, string>;
  invoice_prefix: string | null;
  languages_enabled: Language[];
  default_language: Language;
  branding: Branding;
}

export type SettingsPatch = Partial<
  Omit<TenantSettings, "sampling" | "branding"> & {
    sampling: Partial<Sampling>;
    branding: Partial<Branding>;
  }
>;

// ---- audit -----------------------------------------------------------------------------------
export interface AuditLog {
  id: string;
  tenant_id: string;
  actor_id: string | null;
  actor_role: string;
  action: string;
  entity: string;
  entity_id: string;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
  ip: string | null;
  device_id: string | null;
  user_agent: string | null;
  trace_id: string | null;
  created_at: string;
}

export interface AuditPage {
  items: AuditLog[];
  next_cursor?: string | null;
}

export interface AuditFilters {
  entity?: string;
  entity_id?: string;
  actor_id?: string;
  actor_role?: string;
  action?: string;
  /** ISO instants (the screen converts IST dates). */
  from?: string;
  to?: string;
  q?: string;
  cursor?: string | null;
  limit?: number;
}

export function auditQuery(f: AuditFilters, opts: { paging?: boolean } = {}): string {
  const p = new URLSearchParams();
  const keys = ["entity", "entity_id", "actor_id", "actor_role", "action", "from", "to", "q"];
  for (const k of keys) {
    const v = f[k as keyof AuditFilters];
    if (typeof v === "string" && v.trim()) p.set(k, v.trim());
  }
  if (opts.paging !== false) {
    if (f.cursor) p.set("cursor", f.cursor);
    if (f.limit) p.set("limit", String(f.limit));
  }
  const s = p.toString();
  return s ? `?${s}` : "";
}

export interface DiffRow {
  field: string;
  before: unknown;
  after: unknown;
  changed: boolean;
}

/**
 * Field-by-field before / after for an audit row: every key of either side, changed fields
 * first (in key order), then unchanged ones. Nested objects are compared by JSON value.
 */
export function auditDiff(
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null,
): DiffRow[] {
  const b = before ?? {};
  const a = after ?? {};
  const keys = [...new Set([...Object.keys(b), ...Object.keys(a)])].sort();
  const rows = keys.map((field) => {
    const bv = field in b ? b[field] : undefined;
    const av = field in a ? a[field] : undefined;
    return { field, before: bv, after: av, changed: JSON.stringify(bv) !== JSON.stringify(av) };
  });
  return [...rows.filter((r) => r.changed), ...rows.filter((r) => !r.changed)];
}

/** Value as shown in the diff: strings as is, others as compact JSON, missing as undefined. */
export function diffValue(v: unknown): string | undefined {
  if (v === undefined) return undefined;
  if (typeof v === "string") return v;
  return JSON.stringify(v);
}

// ---- calls -----------------------------------------------------------------------------------
async function fetchCsv(path: string, headers: Headers): Promise<string> {
  const once = () => {
    const token = getAuthToken();
    return fetch(`${API_BASE_URL}/${path}`, {
      headers: { ...headers, ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    });
  };
  if (!getAuthToken()) await session.refresh();
  let res = await once();
  if (res.status === 401) {
    const problem = (await res
      .clone()
      .json()
      .catch(() => ({}))) as { code?: string };
    if (problem.code !== "step_up_required" && (await session.refresh())) res = await once();
  }
  if (!res.ok) {
    const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    throw new ApiError({
      ...data,
      title: typeof data.title === "string" ? data.title : res.statusText,
      status: res.status,
    });
  }
  return res.text();
}

export const adminApi = {
  users: (cursor?: string | null, limit = 50) =>
    authedFetch<UserPage>(
      `v1/users?limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`,
    ),
  user: (id: string) => authedFetch<AdminUser>(`v1/users/${id}`),
  createUser: (body: UserCreateBody, headers: Headers) =>
    authedFetch<AdminUser>("v1/users", { body, headers }),
  updateUser: (id: string, body: UserUpdateBody, headers: Headers) =>
    authedFetch<AdminUser>(`v1/users/${id}`, { method: "PATCH", body, headers }),
  deactivate: (id: string, headers: Headers) =>
    authedFetch<AdminUser>(`v1/users/${id}/deactivate`, { method: "POST", headers }),
  forceLogout: (id: string, headers: Headers) =>
    authedFetch<ForceLogoutResult>(`v1/users/${id}/force-logout`, { method: "POST", headers }),
  devices: (id: string) => authedFetch<{ items: Device[] }>(`v1/users/${id}/devices`),
  bindDevice: (id: string, deviceId: string, headers: Headers) =>
    authedFetch<Device>(`v1/users/${id}/devices/${encodeURIComponent(deviceId)}/bind`, {
      method: "POST",
      headers,
    }),
  reportLost: (id: string, deviceId: string, headers: Headers) =>
    authedFetch<Device>(`v1/users/${id}/devices/${encodeURIComponent(deviceId)}/report-lost`, {
      method: "POST",
      headers,
    }),
  settings: () => authedFetch<TenantSettings>("v1/settings"),
  updateSettings: (body: SettingsPatch, headers: Headers) =>
    authedFetch<TenantSettings>("v1/settings", { method: "PATCH", body, headers }),
  auditLogs: (f: AuditFilters) => authedFetch<AuditPage>(`v1/audit-logs${auditQuery(f)}`),
  exportAuditLogs: (f: AuditFilters, headers: Headers) =>
    fetchCsv(`v1/audit-logs/export${auditQuery(f, { paging: false })}`, headers),
};
