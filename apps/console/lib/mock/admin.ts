/**
 * In-memory administration API for the mock (app/api/mock) so C101-C103 and the step-up flow
 * run without apps/api. Mirrors apps/api/openapi.yaml: `/v1/auth/step-up/send`,
 * `/v1/auth/step-up`, `/v1/users*`, `/v1/settings`, `/v1/audit-logs*` with the same role
 * lists, guard rails and problem codes (`step_up_required`, `otp_invalid`, `otp_locked`,
 * `otp_not_found`, `phone_taken`, `invalid_assignment`, `role_not_grantable`,
 * `cannot_modify_self`, `invalid_settings`, `forbidden`, `not_found`). Every write appends an
 * audit row (`recordAudit`, also used by lib/mock/flags.ts). Holds no real data.
 */
import type { MockActor, MockResult } from "./catalog";

type Json = Record<string, unknown>;

export const MOCK_STEP_UP_OTP = "123456";
export const MOCK_TENANT_ID = "7e2a0000-0000-4000-8000-000000000001";
const STEP_UP_TTL_S = 300;
const MAX_ATTEMPTS = 5;

const USER_READ = ["owner", "director", "tenant_admin", "cluster_head", "auditor"];
const USER_WRITE = ["owner", "director", "tenant_admin"];
const SETTINGS = ["owner", "director", "tenant_admin"];
const AUDIT = ["owner", "director", "auditor", "tenant_admin"];
const STAFF = [
  "owner",
  "director",
  "cluster_head",
  "auditor",
  "store_manager",
  "accountant",
  "field_officer",
  "agronomist",
  "tenant_admin",
];
const LANGS = ["en", "te", "kn", "hi", "mr"];
/** Cluster ids of the analytics mock (`GET /v1/clusters` in lib/mock/analytics.ts names them). */
export const MOCK_CLUSTERS = ["cluster-tg", "cluster-ka"];
const STORES = ["store-wgl", "store-knr", "store-nzb"];

interface User {
  id: string;
  tenant_id: string;
  phone: string;
  name: string;
  role: string;
  store_id: string | null;
  cluster_id: string | null;
  language: string;
  status: string;
  created_at: string;
}

interface Device {
  id: string;
  user_id: string;
  device_id: string;
  platform: string | null;
  model: string | null;
  app_version: string | null;
  first_seen: string;
  last_seen: string;
  status: "pending" | "active" | "revoked" | "lost";
  bound_at: string | null;
  revoked_at: string | null;
}

interface AuditRow {
  id: string;
  tenant_id: string;
  actor_id: string | null;
  actor_role: string;
  action: string;
  entity: string;
  entity_id: string;
  before: Json | null;
  after: Json | null;
  ip: string | null;
  device_id: string | null;
  user_agent: string | null;
  trace_id: string | null;
  created_at: string;
}

interface StepUpState {
  sent: boolean;
  attempts: number;
  lockedUntil: number;
}

/** NF-013 data-principal request (DPDP). Same shape as the API's `DataRequestOut`. */
interface DataRequest {
  id: string;
  type: "deletion" | "access" | "correction" | "grievance";
  status: "received" | "in_progress" | "completed" | "rejected";
  user_id: string;
  farmer_id: string | null;
  reason: string | null;
  subject: string | null;
  requested_changes: Record<string, string> | null;
  due_by: string;
  handled_by: string | null;
  handled_at: string | null;
  resolution_note: string | null;
  created_at: string;
  updated_at: string;
  version: number;
}

interface Db {
  users: User[];
  devices: Device[];
  settings: Json;
  audit: AuditRow[];
  dataRequests: DataRequest[];
  tokens: Map<string, { userId: string; expiresAt: number }>;
  stepUp: Map<string, StepUpState>;
  sessions: Map<string, number>;
  seq: number;
}

const iso = (msAgo: number) => new Date(Date.now() - msAgo).toISOString();
const H = 3_600_000;
const D = 24 * H;

export const MOCK_PHONE_BY_ROLE: Readonly<Record<string, string>> = {
  owner: "+919876543210",
  director: "+919000000002",
  cluster_head: "+919000000003",
  store_manager: "+919000000004",
  auditor: "+919000000005",
  accountant: "+919000000006",
  field_officer: "+919000000007",
  agronomist: "+919000000008",
  tenant_admin: "+919000000009",
};

const NAMES: Record<string, string> = {
  owner: "Suresh Patil",
  director: "Anita Rao",
  cluster_head: "Mahesh Goud",
  store_manager: "Priya Reddy",
  auditor: "Farhan Ali",
  accountant: "Kavya Iyer",
  field_officer: "Ravi Kumar",
  agronomist: "Dr. Lata Deshmukh",
  tenant_admin: "Arjun Mehta",
};

export const DEFAULT_SETTINGS: Json = {
  consent_version: "2026-09-v1",
  geofence_radius_m: 150,
  meeting_point_radius_m: null,
  min_visit_duration_s: 300,
  auto_duty_end_local_time: "20:00",
  idle_end_minutes: 60,
  location_policy_version: "2026-09-v1",
  sampling: { moving_s: 120, stationary_s: 600, upload_s: 900 },
  ta_rate_per_km_paise: 300,
  store_manager_max_credit_limit_paise: 5_000_000,
  credit_due_days: 90,
  day_close_variance_threshold_paise: 50_000,
  webhook_replay_window_s: 300,
  legal_name: null,
  gstin_by_state: {},
  invoice_prefix: null,
  languages_enabled: ["en", "te", "kn", "hi", "mr"],
  default_language: "en",
  branding: {
    app_name_agent: null,
    app_name_farmer: null,
    primary_colour: "#1F6B3A",
    logo_blob_uri: null,
    support_phone: null,
  },
};

function seed(): Db {
  const users: User[] = Object.keys(NAMES).map((role, i) => ({
    id: `u-${role}`,
    tenant_id: MOCK_TENANT_ID,
    phone: MOCK_PHONE_BY_ROLE[role] ?? "+919000000000",
    name: NAMES[role] ?? role,
    role,
    store_id: role === "store_manager" || role === "accountant" ? "store-wgl" : null,
    cluster_id:
      role === "cluster_head" || role === "field_officer" ? (MOCK_CLUSTERS[0] ?? null) : null,
    language: role === "field_officer" ? "te" : "en",
    status: "active",
    created_at: iso((200 - i) * D),
  }));
  users.push(
    {
      id: "u-fo-lakshmi",
      tenant_id: MOCK_TENANT_ID,
      phone: "+919000000017",
      name: "Lakshmi Devi",
      role: "field_officer",
      store_id: null,
      cluster_id: MOCK_CLUSTERS[0] ?? null,
      language: "te",
      status: "active",
      created_at: iso(120 * D),
    },
    {
      id: "u-fo-kiran",
      tenant_id: MOCK_TENANT_ID,
      phone: "+919000000027",
      name: "Kiran Naik",
      role: "field_officer",
      store_id: null,
      cluster_id: MOCK_CLUSTERS[1] ?? null,
      language: "kn",
      status: "disabled",
      created_at: iso(90 * D),
    },
  );
  const device = (
    id: string,
    user: string,
    deviceId: string,
    status: Device["status"],
    model: string,
    daysAgo: number,
  ): Device => ({
    id,
    user_id: user,
    device_id: deviceId,
    platform: "android",
    model,
    app_version: "1.4.0",
    first_seen: iso(daysAgo * D),
    last_seen: iso(status === "pending" ? 2 * H : 6 * H),
    status,
    bound_at: status === "pending" ? null : iso(daysAgo * D),
    revoked_at: status === "lost" || status === "revoked" ? iso(3 * D) : null,
  });
  const devices = [
    device("d-0001", "u-field_officer", "android-7f3a91", "active", "Redmi Note 12", 60),
    device("d-0002", "u-field_officer", "android-c0ffee", "pending", "Samsung Galaxy M14", 0),
    device("d-0003", "u-fo-lakshmi", "android-5b2e10", "lost", "Realme C55", 40),
    device("d-0004", "u-fo-lakshmi", "android-9d8e77", "active", "Redmi 13C", 3),
    device("d-0005", "u-store_manager", "android-51de01", "active", "Moto G54", 80),
  ];
  const settings: Json = structuredClone({
    ...DEFAULT_SETTINGS,
    legal_name: "Farmers Care Centre Pvt Ltd",
    gstin_by_state: { "36": "36ABCDE1234F1Z5" },
    invoice_prefix: "FCC",
    languages_enabled: ["en", "te", "hi"],
  });
  const audit: AuditRow[] = [
    auditRow(
      1,
      "u-owner",
      "owner",
      "user.update",
      "user",
      "u-fo-lakshmi",
      { store_id: null },
      { store_id: null, cluster_id: MOCK_CLUSTERS[0] },
      9 * D,
    ),
    auditRow(
      2,
      "u-tenant_admin",
      "tenant_admin",
      "tenant_settings.update",
      "tenant",
      MOCK_TENANT_ID,
      { geofence_radius_m: 100 },
      { geofence_radius_m: 150 },
      8 * D,
    ),
    auditRow(
      3,
      "u-director",
      "director",
      "device.report_lost",
      "device",
      "d-0003",
      null,
      { user_id: "u-fo-lakshmi", device_id: "android-5b2e10", revoked_sessions: 1 },
      3 * D,
    ),
    auditRow(
      4,
      "u-owner",
      "owner",
      "user.update",
      "user",
      "u-fo-kiran",
      { status: "active" },
      { status: "disabled" },
      2 * D,
    ),
    auditRow(5, "u-auditor", "auditor", "auth.step_up", "user", "u-auditor", null, null, 1 * D),
  ];
  return {
    users,
    devices,
    settings,
    audit,
    dataRequests: seedDataRequests(),
    tokens: new Map(),
    stepUp: new Map(),
    sessions: new Map([
      ["u-field_officer", 2],
      ["u-fo-lakshmi", 1],
      ["u-store_manager", 1],
    ]),
    seq: 100,
  };
}

function auditRow(
  n: number,
  actorId: string,
  role: string,
  action: string,
  entity: string,
  entityId: string,
  before: Json | null,
  after: Json | null,
  msAgo: number,
): AuditRow {
  return {
    id: `a0000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
    tenant_id: MOCK_TENANT_ID,
    actor_id: actorId,
    actor_role: role,
    action,
    entity,
    entity_id: entityId,
    before,
    after,
    ip: "10.0.0.12",
    device_id: null,
    user_agent: "Mozilla/5.0 (console)",
    trace_id: `trace-${n}`,
    created_at: iso(msAgo),
  };
}

/**
 * NF-013 queue seed: one request of every type, two already handled, one deletion past its
 * statutory deadline (so the overdue badge and the oldest-due-first order are visible).
 * `iso()` takes milliseconds ago, so a negative argument is a future deadline.
 */
function seedDataRequests(): DataRequest[] {
  const row = (
    r: Omit<DataRequest, "version" | "updated_at"> & { updated_at?: string },
  ): DataRequest => ({ ...r, updated_at: r.updated_at ?? r.created_at, version: 1 });
  return [
    row({
      id: "dr-0001",
      type: "deletion",
      status: "received",
      user_id: "u-farmer-ramesh",
      farmer_id: "farmer-ramesh",
      reason: "Ramesh Yadav asked us to delete his account after moving to another dealer.",
      subject: null,
      requested_changes: null,
      due_by: iso(3 * D),
      handled_by: null,
      handled_at: null,
      resolution_note: null,
      created_at: iso(33 * D),
    }),
    row({
      id: "dr-0002",
      type: "access",
      status: "received",
      user_id: "u-farmer-sunita",
      farmer_id: "farmer-sunita",
      reason: "Sunita Bai wants a copy of everything we hold about her.",
      subject: null,
      requested_changes: null,
      due_by: iso(-6 * D),
      handled_by: null,
      handled_at: null,
      resolution_note: null,
      created_at: iso(24 * D),
    }),
    row({
      id: "dr-0003",
      type: "correction",
      status: "in_progress",
      user_id: "u-farmer-imran",
      farmer_id: "farmer-imran",
      reason: "The village and the spelling of the name are wrong on the receipts.",
      subject: null,
      requested_changes: {
        name: "Imran Shaikh",
        village: "Kothapally",
        phone: "+919000000123",
      },
      due_by: iso(-11 * D),
      handled_by: "u-tenant_admin",
      handled_at: iso(1 * D),
      resolution_note: null,
      created_at: iso(19 * D),
      updated_at: iso(1 * D),
    }),
    row({
      id: "dr-0004",
      type: "grievance",
      status: "received",
      user_id: "u-farmer-lakshmi",
      farmer_id: "farmer-lakshmi",
      reason: "Campaign messages keep arriving after the farmer withdrew consent.",
      subject: "Campaign messages after withdrawing consent",
      requested_changes: null,
      due_by: iso(-18 * D),
      handled_by: null,
      handled_at: null,
      resolution_note: null,
      created_at: iso(12 * D),
    }),
    row({
      id: "dr-0005",
      type: "access",
      status: "completed",
      user_id: "u-field_officer",
      farmer_id: null,
      reason: "Field officer asked for his own location history.",
      subject: null,
      requested_changes: null,
      due_by: iso(12 * D),
      handled_by: "u-owner",
      handled_at: iso(14 * D),
      resolution_note: "Export shared over the registered number.",
      created_at: iso(42 * D),
      updated_at: iso(14 * D),
    }),
    row({
      id: "dr-0006",
      type: "grievance",
      status: "rejected",
      user_id: "u-farmer-kiran",
      farmer_id: "farmer-kiran",
      reason: "Complaint about a price, not about personal data.",
      subject: "Price complaint",
      requested_changes: null,
      due_by: iso(20 * D),
      handled_by: "u-tenant_admin",
      handled_at: iso(22 * D),
      resolution_note: "Not a data-protection grievance; routed to the store manager.",
      created_at: iso(50 * D),
      updated_at: iso(22 * D),
    }),
  ];
}

let db: Db = seed();

export function resetMockAdmin(): void {
  db = seed();
}

// ---- helpers ---------------------------------------------------------------------------------
function problem(status: number, code: string, detail?: string, extra?: Json): MockResult {
  return {
    status,
    json: {
      type: `https://farmerapp.dev/problems/${code}`,
      title: code,
      status,
      code,
      detail,
      ...extra,
    },
    headers: { "content-type": "application/problem+json" },
  };
}
const ok = (json: unknown, status = 200): MockResult => ({ status, json });
const forbidden = () => problem(403, "forbidden", "Your role does not allow this action.");
const notFound = (what: string) => problem(404, "not_found", `${what} not found.`);

/** Append an audit row (the real API does this in the same transaction as the write). */
export function recordAudit(
  actor: MockActor,
  action: string,
  entity: string,
  entityId: string,
  before: Json | null,
  after: Json | null,
): void {
  db.seq += 1;
  db.audit.push({
    ...auditRow(db.seq, actor.id, actor.role, action, entity, entityId, before, after, 0),
    created_at: new Date().toISOString(),
  });
}

export function mockUserName(id: string | null): string | null {
  return db.users.find((u) => u.id === id)?.name ?? null;
}

function stepUpOk(headers: Headers, actor: MockActor): boolean {
  const token = headers.get("x-step-up-token")?.trim();
  if (!token) return false;
  const held = db.tokens.get(token);
  return !!held && held.userId === actor.id && held.expiresAt > Date.now();
}

/** Step-up check for the other mock modules (WC-009 close, WC-013 exports, DX-012 decisions). */
export function mockStepUpOk(headers: Headers, actor: MockActor): boolean {
  return stepUpOk(headers, actor);
}

const stepUpRequired = () =>
  problem(401, "step_up_required", "This action needs a fresh one-time code.", {
    step_up_url: "/v1/auth/step-up/send",
  });

function visibleUsers(actor: MockActor): User[] {
  if (actor.role === "cluster_head") {
    const me = db.users.find((u) => u.id === actor.id);
    return db.users.filter(
      (u) => u.id === actor.id || (me?.cluster_id && u.cluster_id === me.cluster_id),
    );
  }
  return db.users;
}

function guardOwner(actor: MockActor, targetRole: string | null, newRole?: string | null) {
  if (actor.role === "owner") return null;
  if (targetRole === "owner" || newRole === "owner")
    return problem(403, "role_not_grantable", "Only an owner can grant or change the owner role.");
  return null;
}

function checkAssignment(body: Json): MockResult | null {
  if (body.store_id != null && !STORES.includes(String(body.store_id)))
    return problem(422, "invalid_assignment", "Unknown store.", { field: "store_id" });
  if (body.cluster_id != null && !MOCK_CLUSTERS.includes(String(body.cluster_id)))
    return problem(422, "invalid_assignment", "Unknown cluster.", { field: "cluster_id" });
  return null;
}

const DEVICE_ORDER = ["pending", "active", "lost", "revoked"] as const;

/** `GET /v1/users` rows carry the device status and the most recently seen device. */
function withDeviceStatus(u: User): Json {
  const devices = db.devices.filter((d) => d.user_id === u.id);
  const latest = [...devices].sort((a, b) => b.last_seen.localeCompare(a.last_seen))[0];
  return {
    ...u,
    device_status: DEVICE_ORDER.find((st) => devices.some((d) => d.status === st)) ?? "none",
    latest_device: latest
      ? {
          device_id: latest.device_id,
          platform: latest.platform,
          model: latest.model,
          status: latest.status,
          last_seen: latest.last_seen,
        }
      : null,
  };
}

function page<T>(items: T[], query: URLSearchParams): MockResult {
  const limit = Math.min(200, Math.max(1, Number(query.get("limit") ?? 50) || 50));
  const start = Number(query.get("cursor") ?? 0) || 0;
  const slice = items.slice(start, start + limit);
  const next = start + limit < items.length ? String(start + limit) : null;
  return ok({ items: slice, next_cursor: next });
}

// ---- settings validation (ranges of TenantSettings) -----------------------------------------
type Range = [number, number];
const RANGES: Record<string, Range> = {
  geofence_radius_m: [10, 2000],
  meeting_point_radius_m: [10, 2000],
  min_visit_duration_s: [0, 86_400],
  idle_end_minutes: [5, 720],
  ta_rate_per_km_paise: [0, 10_000],
  store_manager_max_credit_limit_paise: [0, 10_000_000_000],
  credit_due_days: [1, 730],
  day_close_variance_threshold_paise: [0, 10_000_000],
  webhook_replay_window_s: [30, 86_400],
};
const SAMPLING_RANGES: Record<string, Range> = {
  moving_s: [30, 3600],
  stationary_s: [60, 7200],
  upload_s: [60, 86_400],
};
const SETTINGS_KEYS = new Set(Object.keys(DEFAULT_SETTINGS));

function validateSettings(
  merged: Json,
  patch: Json,
): Array<{ loc: string[]; msg: string; type: string }> {
  const errors: Array<{ loc: string[]; msg: string; type: string }> = [];
  const bad = (loc: string[], msg: string) =>
    errors.push({ loc: ["body", ...loc], msg, type: "value_error" });
  for (const [k, [lo, hi]] of Object.entries(RANGES)) {
    const v = merged[k];
    if (v === null && k === "meeting_point_radius_m") continue;
    if (typeof v !== "number" || !Number.isInteger(v) || v < lo || v > hi)
      bad([k], `must be between ${lo} and ${hi}`);
  }
  const sampling = (merged.sampling ?? {}) as Json;
  for (const [k, [lo, hi]] of Object.entries(SAMPLING_RANGES)) {
    const v = sampling[k];
    if (typeof v !== "number" || !Number.isInteger(v) || v < lo || v > hi)
      bad(["sampling", k], `must be between ${lo} and ${hi}`);
  }
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(String(merged.auto_duty_end_local_time)))
    bad(["auto_duty_end_local_time"], "HH:MM");
  const langs = merged.languages_enabled;
  if (!Array.isArray(langs) || langs.length === 0 || langs.some((l) => !LANGS.includes(String(l))))
    bad(["languages_enabled"], "invalid");
  else if (!langs.includes(merged.default_language)) bad(["default_language"], "must be enabled");
  if (merged.invoice_prefix !== null && !/^[A-Z0-9]{1,8}$/.test(String(merged.invoice_prefix)))
    bad(["invoice_prefix"], "A-Z 0-9, max 8");
  const gst = (merged.gstin_by_state ?? {}) as Json;
  for (const [state, v] of Object.entries(gst))
    if (!/^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(String(v)))
      bad(["gstin_by_state", state], "invalid GSTIN");
  const branding = (merged.branding ?? {}) as Json;
  if (!/^#[0-9A-Fa-f]{6}$/.test(String(branding.primary_colour)))
    bad(["branding", "primary_colour"], "#RRGGBB");
  for (const k of ["app_name_agent", "app_name_farmer"]) {
    const v = branding[k];
    if (v !== null && (typeof v !== "string" || v.length < 1 || v.length > 40))
      bad(["branding", k], "1-40 characters");
  }
  if (branding.support_phone !== null && !/^\+?[0-9]{8,15}$/.test(String(branding.support_phone)))
    bad(["branding", "support_phone"], "invalid phone");
  void patch;
  return errors;
}

function patchSettings(body: Json, actor: MockActor): MockResult {
  const unknown = Object.keys(body).filter((k) => !SETTINGS_KEYS.has(k));
  if (unknown.length)
    return problem(422, "validation_error", "Request validation failed.", {
      errors: unknown.map((k) => ({
        loc: ["body", k],
        msg: "extra field",
        type: "extra_forbidden",
      })),
    });
  const old = structuredClone(db.settings);
  const merged: Json = structuredClone(db.settings);
  for (const [k, v] of Object.entries(body)) {
    if ((k === "sampling" || k === "branding") && v && typeof v === "object") {
      const base = { ...(merged[k] as Json) };
      for (const [nk, nv] of Object.entries(v as Json))
        base[nk] = nv === null && k === "sampling" ? (DEFAULT_SETTINGS.sampling as Json)[nk] : nv;
      merged[k] = base;
    } else
      merged[k] =
        v === null && k !== "meeting_point_radius_m" && k !== "legal_name" && k !== "invoice_prefix"
          ? structuredClone(DEFAULT_SETTINGS[k])
          : v;
  }
  const errors = validateSettings(merged, body);
  if (errors.length)
    return problem(422, "invalid_settings", "Some settings are out of range.", { errors });
  const changed = Object.keys(merged).filter(
    (k) => JSON.stringify(merged[k]) !== JSON.stringify(old[k]),
  );
  db.settings = merged;
  if (changed.length) {
    recordAudit(
      actor,
      "tenant_settings.update",
      "tenant",
      MOCK_TENANT_ID,
      Object.fromEntries(changed.map((k) => [k, old[k]])),
      Object.fromEntries(changed.map((k) => [k, merged[k]])),
    );
  }
  return ok(db.settings);
}

// ---- audit -----------------------------------------------------------------------------------
function listAudit(query: URLSearchParams): AuditRow[] {
  let rows = [...db.audit].reverse();
  const eq = (k: keyof AuditRow) => {
    const v = query.get(k);
    if (v) rows = rows.filter((r) => r[k] === v);
  };
  eq("entity");
  eq("entity_id");
  eq("actor_id");
  eq("actor_role");
  const action = query.get("action");
  if (action)
    rows = rows.filter((r) =>
      action.endsWith(".") ? r.action.startsWith(action) : r.action === action,
    );
  const q = query.get("q")?.toLowerCase();
  if (q) rows = rows.filter((r) => r.entity_id.toLowerCase().startsWith(q));
  const from = query.get("from");
  if (from) rows = rows.filter((r) => r.created_at >= new Date(from).toISOString());
  const to = query.get("to");
  if (to) rows = rows.filter((r) => r.created_at <= new Date(to).toISOString());
  return rows;
}

const csvCell = (v: unknown): string => {
  let s = v === null || v === undefined ? "" : typeof v === "string" ? v : JSON.stringify(v);
  if (/^[=+\-@]/.test(s)) s = `'${s}`;
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

// ---- data-principal requests (NF-013) --------------------------------------------------------
const DATA_REQUEST_ROLES = ["owner", "tenant_admin"];

/** Allowed status moves; anything else is 409 `invalid_transition` (the API's rule). */
const TRANSITIONS: Record<DataRequest["status"], ReadonlyArray<DataRequest["status"]>> = {
  received: ["in_progress", "rejected"],
  in_progress: ["completed", "rejected"],
  completed: [],
  rejected: [],
};

/** `overdue` is derived by the API on read; the stored row only carries the deadline. */
const withOverdue = (r: DataRequest): Json => ({
  ...r,
  overdue:
    (r.status === "received" || r.status === "in_progress") && Date.parse(r.due_by) <= Date.now(),
});

const touch = (r: DataRequest, actor: MockActor): void => {
  r.updated_at = new Date().toISOString();
  r.version += 1;
  r.handled_by = actor.id;
  r.handled_at = r.updated_at;
};

/**
 * `/v1/admin/data-requests*`. Erasure keeps the classes the law requires us to keep: GST
 * invoices and ledger entries stay for 8 financial years (SPEC 11 retention), so the operator
 * can see that "delete everything" never silently drops the books.
 */
function handleDataRequests(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor,
  headers: Headers,
): MockResult {
  const id = path[2];
  const action = path[3];
  if (!DATA_REQUEST_ROLES.includes(actor.role)) return forbidden();

  if (id === undefined) {
    if (method !== "GET") return problem(404, "not_found", "No such route.");
    const type = query.get("type");
    const status = query.get("status");
    const rows = db.dataRequests
      .filter((r) => (!type || r.type === type) && (!status || r.status === status))
      .sort((a, b) => a.due_by.localeCompare(b.due_by) || a.id.localeCompare(b.id))
      .map(withOverdue);
    return page(rows, query);
  }

  const request = db.dataRequests.find((r) => r.id === id);
  if (!request) return notFound("Data request");

  if (action === undefined && method === "PATCH") {
    const next = String(body.status ?? "");
    if (!TRANSITIONS[request.status])
      return problem(422, "validation_error", "Unknown status.", {
        errors: [{ loc: ["body", "status"], msg: "invalid", type: "enum" }],
      });
    if (!(TRANSITIONS[request.status] as readonly string[]).includes(next))
      return problem(
        409,
        "invalid_transition",
        `A ${request.status} request cannot move to ${next || "(nothing)"}.`,
      );
    const before = { status: request.status };
    request.status = next as DataRequest["status"];
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (note) request.resolution_note = note;
    touch(request, actor);
    recordAudit(actor, "data_request.update", "data_request", request.id, before, {
      status: request.status,
      resolution_note: request.resolution_note,
    });
    return ok(withOverdue(request));
  }

  if (action === "apply-correction" && method === "POST") {
    if (request.type !== "correction")
      return problem(409, "invalid_transition", "Only a correction request can be applied.");
    if (request.status === "completed" || request.status === "rejected")
      return problem(409, "invalid_transition", "This request is already closed.");
    const blocked = stepUpOk(headers, actor) ? null : stepUpRequired();
    if (blocked) return blocked;
    const applied = { ...(request.requested_changes ?? {}) };
    request.status = "completed";
    request.resolution_note = `Applied ${Object.keys(applied).length} corrected field(s).`;
    touch(request, actor);
    recordAudit(actor, "data_request.apply_correction", "data_request", request.id, null, applied);
    return ok({ applied, request: withOverdue(request) });
  }

  if (action === "erase" && method === "POST") {
    if (request.type !== "deletion")
      return problem(409, "invalid_transition", "Only a deletion request can be erased.");
    if (request.status === "completed" || request.status === "rejected")
      return problem(409, "invalid_transition", "This request is already closed.");
    const blocked = stepUpOk(headers, actor) ? null : stepUpRequired();
    if (blocked) return blocked;
    const erased = [
      "farmer_profile",
      "farmer_contact",
      "consent_history",
      "visit_photos",
      "diagnosis_images",
      "campaign_messages",
      "device_bindings",
    ];
    const retained = [
      {
        class: "financial_records",
        until: new Date(Date.now() + 8 * 365 * D).toISOString(),
        reason: "GST invoices and ledger entries are kept for 8 financial years.",
      },
      {
        class: "audit_log",
        until: new Date(Date.now() + 8 * 365 * D).toISOString(),
        reason: "Tamper-evident audit rows cannot be deleted; the farmer id is pseudonymised.",
      },
    ];
    request.status = "completed";
    request.resolution_note = `Erased ${erased.length} data classes; ${retained.length} retained by law.`;
    touch(request, actor);
    recordAudit(actor, "data_request.erase", "data_request", request.id, null, {
      erased,
      retained: retained.map((r) => r.class),
    });
    return ok({ erased, retained, request: withOverdue(request) });
  }

  if (action === "export" && method === "GET") {
    recordAudit(actor, "data_request.export", "data_request", request.id, null, {
      farmer_id: request.farmer_id,
    });
    return ok({
      generated_at: new Date().toISOString(),
      request_id: request.id,
      data_principal: {
        user_id: request.user_id,
        farmer_id: request.farmer_id,
        name: mockUserName(request.user_id) ?? "Sunita Bai",
        phone: "+91******4321",
        language: "te",
      },
      consents: [
        { purpose: "service", version: "2026-09-v1", granted_at: iso(120 * D), withdrawn_at: null },
        {
          purpose: "marketing",
          version: "2026-09-v1",
          granted_at: iso(120 * D),
          withdrawn_at: iso(20 * D),
        },
      ],
      farms: [{ id: "plot-1", crop: "cotton", area_acres: 3.5, village: "Kothapally" }],
      orders: [{ id: "ord-1", placed_at: iso(60 * D), total_paise: 452_000, status: "delivered" }],
      visits: [{ id: "visit-1", at: iso(58 * D), officer: "Ravi Kumar", verified: true }],
      diagnoses: [{ id: "dx-1", at: iso(45 * D), crop: "cotton", problem: "Aphids" }],
      messages: [{ id: "msg-1", at: iso(21 * D), channel: "whatsapp", campaign: "Kharif offers" }],
    });
  }

  return problem(404, "not_found", "No such route.");
}

// ---- handler ---------------------------------------------------------------------------------
/** `/auth/step-up*`, `/users*`, `/settings`, `/audit-logs*`, `/admin/data-requests*`. */
export function handleAdmin(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor | null,
  headers: Headers,
): MockResult | null {
  const [a, b, c, d, e] = path;
  const isStepUp = a === "auth" && b === "step-up";
  const isDataRequests = a === "admin" && b === "data-requests";
  if (!isStepUp && !isDataRequests && a !== "users" && a !== "settings" && a !== "audit-logs")
    return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  if (isDataRequests) return handleDataRequests(method, path, query, body, actor, headers);
  const role = actor.role;
  const allow = (roles: readonly string[]) => roles.includes(role);
  const now = Date.now();

  if (isStepUp) {
    const state = db.stepUp.get(actor.id) ?? { sent: false, attempts: 0, lockedUntil: 0 };
    db.stepUp.set(actor.id, state);
    if (state.lockedUntil > now)
      return problem(423, "otp_locked", "Too many wrong attempts.", {
        retry_after: Math.ceil((state.lockedUntil - now) / 1000),
      });
    if (method === "POST" && c === "send") {
      state.sent = true;
      state.attempts = 0;
      const phone = MOCK_PHONE_BY_ROLE[role] ?? "+919876543210";
      return ok(
        {
          challenge_id: `stepup-${now}`,
          phone_masked: `+91******${phone.slice(-4)}`,
          channel: "sms",
          expires_in: 300,
          resend_after: 30,
          resends_left: 3,
        },
        202,
      );
    }
    if (method === "POST" && c === undefined) {
      if (!state.sent) return problem(404, "otp_not_found", "Request a code first.");
      if (body.code !== MOCK_STEP_UP_OTP) {
        state.attempts += 1;
        if (state.attempts >= MAX_ATTEMPTS) {
          state.lockedUntil = now + 15 * 60_000;
          return problem(423, "otp_locked", "Too many wrong attempts.", { retry_after: 900 });
        }
        return problem(401, "otp_invalid", "Incorrect code.", {
          attempts_left: MAX_ATTEMPTS - state.attempts,
        });
      }
      state.sent = false;
      const token = `mock-stepup-${actor.id}-${now}-${Math.random().toString(36).slice(2)}`;
      db.tokens.set(token, { userId: actor.id, expiresAt: now + STEP_UP_TTL_S * 1000 });
      recordAudit(actor, "auth.step_up", "user", actor.id, null, null);
      return ok({ step_up_token: token, expires_in: STEP_UP_TTL_S });
    }
    return problem(404, "not_found", "No such route.");
  }

  const needStepUp = () => (stepUpOk(headers, actor) ? null : stepUpRequired());

  if (a === "settings") {
    if (b === undefined && method === "GET") return allow(SETTINGS) ? ok(db.settings) : forbidden();
    if (b === undefined && method === "PATCH") {
      if (!allow(SETTINGS)) return forbidden();
      return needStepUp() ?? patchSettings(body, actor);
    }
    if (b === "public" && method === "GET") {
      const s = db.settings;
      return ok({
        geofence_radius_m: s.geofence_radius_m,
        meeting_point_radius_m: s.meeting_point_radius_m,
        min_visit_duration_s: s.min_visit_duration_s,
        auto_duty_end_local_time: s.auto_duty_end_local_time,
        idle_end_minutes: s.idle_end_minutes,
        location_policy_version: s.location_policy_version,
        sampling: s.sampling,
        languages_enabled: s.languages_enabled,
        default_language: s.default_language,
        branding: s.branding,
      });
    }
    return problem(404, "not_found", "No such route.");
  }

  if (a === "audit-logs") {
    if (!allow(AUDIT)) return forbidden();
    if (method === "GET" && b === undefined) return page(listAudit(query), query);
    if (method === "GET" && b === "export") {
      const blocked = needStepUp();
      if (blocked) return blocked;
      const rows = listAudit(query);
      const cols = [
        "created_at",
        "action",
        "entity",
        "entity_id",
        "actor_id",
        "actor_role",
        "ip",
        "device_id",
        "user_agent",
        "trace_id",
        "before",
        "after",
        "id",
      ] as const;
      const text =
        [cols.join(","), ...rows.map((r) => cols.map((k) => csvCell(r[k])).join(","))].join("\n") +
        "\n";
      recordAudit(actor, "audit_log.export", "audit_log", MOCK_TENANT_ID, null, {
        filters: Object.fromEntries(query.entries()),
        rows: rows.length,
      });
      return { status: 200, text, headers: { "content-type": "text/csv; charset=utf-8" } };
    }
    return problem(404, "not_found", "No such route.");
  }

  // ---- users ----
  if (b === undefined) {
    if (method === "GET")
      return allow(USER_READ)
        ? page(visibleUsers(actor).map(withDeviceStatus), query)
        : forbidden();
    if (method === "POST") {
      if (!allow(USER_WRITE)) return forbidden();
      const blocked = needStepUp();
      if (blocked) return blocked;
      const newRole = String(body.role ?? "");
      if (!STAFF.includes(newRole))
        return problem(422, "validation_error", "Request validation failed.", {
          errors: [{ loc: ["body", "role"], msg: "invalid role", type: "enum" }],
        });
      const guard = guardOwner(actor, null, newRole);
      if (guard) return guard;
      const phone = String(body.phone ?? "");
      if (!/^\+91[6-9]\d{9}$/.test(phone))
        return problem(422, "validation_error", "Request validation failed.", {
          errors: [{ loc: ["body", "phone"], msg: "invalid", type: "value_error" }],
        });
      const name = typeof body.name === "string" ? body.name.trim() : "";
      if (!name)
        return problem(422, "validation_error", "Request validation failed.", {
          errors: [{ loc: ["body", "name"], msg: "required", type: "missing" }],
        });
      const assignment = checkAssignment(body);
      if (assignment) return assignment;
      if (db.users.some((u) => u.phone === phone))
        return problem(409, "phone_taken", "A user with this phone exists.");
      db.seq += 1;
      const user: User = {
        id: `u-new-${db.seq}`,
        tenant_id: MOCK_TENANT_ID,
        phone,
        name,
        role: newRole,
        store_id: (body.store_id as string | null) ?? null,
        cluster_id: (body.cluster_id as string | null) ?? null,
        language:
          typeof body.language === "string" ? body.language : String(db.settings.default_language),
        status: "active",
        created_at: new Date().toISOString(),
      };
      db.users.push(user);
      recordAudit(actor, "user.create", "user", user.id, null, {
        name,
        role: newRole,
        phone: `+91******${phone.slice(-4)}`,
      });
      return ok(user, 201);
    }
    return problem(404, "not_found", "No such route.");
  }

  const user = visibleUsers(actor).find((u) => u.id === b);
  if (!allow(USER_READ)) return forbidden();
  if (!user) return notFound("User");

  if (c === undefined && method === "GET") return ok(user);
  if (c === undefined && method === "PATCH") {
    if (!allow(USER_WRITE)) return forbidden();
    const guarded = "role" in body || "status" in body;
    const guard = guardOwner(actor, user.role, body.role as string | undefined);
    if (guard) return guard;
    if (guarded && user.id === actor.id)
      return problem(403, "cannot_modify_self", "You cannot change your own role or status.");
    if (guarded) {
      const blocked = needStepUp();
      if (blocked) return blocked;
    }
    if (body.role !== undefined && body.role !== null && !STAFF.includes(String(body.role)))
      return problem(422, "validation_error", "Request validation failed.", {
        errors: [{ loc: ["body", "role"], msg: "invalid role", type: "enum" }],
      });
    const assignment = checkAssignment(body);
    if (assignment) return assignment;
    const before: Json = {};
    const after: Json = {};
    for (const k of ["name", "role", "status", "store_id", "cluster_id"] as const) {
      if (!(k in body)) continue;
      const v = body[k];
      if ((k === "name" || k === "role" || k === "status") && (v === null || v === undefined))
        continue;
      if (user[k] !== v) {
        before[k] = user[k];
        after[k] = v;
        (user as unknown as Json)[k] = v;
      }
    }
    if (Object.keys(after).length)
      recordAudit(actor, "user.update", "user", user.id, before, after);
    if (after.status === "disabled") db.sessions.set(user.id, 0);
    return ok(user);
  }
  if (c === "deactivate" && method === "POST") {
    if (!allow(USER_WRITE)) return forbidden();
    const guard = guardOwner(actor, user.role);
    if (guard) return guard;
    if (user.id === actor.id)
      return problem(403, "cannot_modify_self", "You cannot change your own role or status.");
    const blocked = needStepUp();
    if (blocked) return blocked;
    if (user.status !== "disabled") {
      recordAudit(
        actor,
        "user.update",
        "user",
        user.id,
        { status: user.status },
        { status: "disabled" },
      );
      user.status = "disabled";
    }
    db.sessions.set(user.id, 0);
    return ok(user);
  }
  if (c === "force-logout" && method === "POST") {
    if (!allow(USER_WRITE)) return forbidden();
    const guard = guardOwner(actor, user.role);
    if (guard) return guard;
    const blocked = needStepUp();
    if (blocked) return blocked;
    const revoked = db.sessions.get(user.id) ?? 0;
    db.sessions.set(user.id, 0);
    const at = new Date().toISOString();
    recordAudit(actor, "user.force_logout", "user", user.id, null, {
      revoked_sessions: revoked,
      tokens_valid_after: at,
    });
    return ok({ user_id: user.id, revoked_sessions: revoked, tokens_valid_after: at });
  }
  if (c === "devices" && d === undefined && method === "GET")
    return ok({ items: db.devices.filter((x) => x.user_id === user.id) });
  if (c === "devices" && d && (e === "bind" || e === "report-lost") && method === "POST") {
    if (!allow(USER_WRITE)) return forbidden();
    const guard = guardOwner(actor, user.role);
    if (guard) return guard;
    const blocked = needStepUp();
    if (blocked) return blocked;
    const device = db.devices.find(
      (x) => x.user_id === user.id && x.device_id === decodeURIComponent(d),
    );
    if (!device) return notFound("Device");
    const at = new Date().toISOString();
    if (e === "bind") {
      const unbound: string[] = [];
      if (user.role === "field_officer")
        for (const other of db.devices)
          if (other.user_id === user.id && other !== device && other.status === "active") {
            other.status = "revoked";
            other.revoked_at = at;
            unbound.push(other.device_id);
          }
      device.status = "active";
      device.bound_at = at;
      device.revoked_at = null;
      recordAudit(actor, "device.bind", "device", device.id, null, {
        user_id: user.id,
        device_id: device.device_id,
        unbound,
      });
    } else {
      const revoked = device.status === "active" ? 1 : 0;
      device.status = "lost";
      device.revoked_at = at;
      recordAudit(actor, "device.report_lost", "device", device.id, null, {
        user_id: user.id,
        device_id: device.device_id,
        revoked_sessions: revoked,
      });
    }
    return ok(device);
  }
  return problem(404, "not_found", `No mock for ${method} /${path.join("/")}`);
}
