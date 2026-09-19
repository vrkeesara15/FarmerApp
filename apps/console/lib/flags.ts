/**
 * Validation flags (WC-010, VA-002, VA-003): typed `/v1/flags*` calls, the SPEC 6.1 state
 * machine and SLA helpers used by C70 (inbox) and C71 (flag detail). Shapes mirror
 * apps/api/openapi.yaml (`FlagPage`, `FlagOut`, `FlagDetailOut`).
 */
import { authedFetch } from "./api";

export const FLAG_STATUSES = [
  "open",
  "in_review",
  "escalated",
  "resolved_valid",
  "resolved_fixed",
  "resolved_action",
] as const;
export type FlagStatus = (typeof FLAG_STATUSES)[number];
export const UNRESOLVED_STATUSES: ReadonlyArray<FlagStatus> = ["open", "in_review", "escalated"];

export const FLAG_SEVERITIES = ["high", "medium", "low"] as const;
export type FlagSeverity = (typeof FLAG_SEVERITIES)[number];

export const SUBJECT_TYPES = ["farmer", "employee", "visit", "store"] as const;
export type SubjectType = (typeof SUBJECT_TYPES)[number];

/** Roles that read the inbox (x-roles of listFlags). Field officers see their own flags. */
export const FLAG_READ_ROLES: ReadonlyArray<string> = [
  "owner",
  "director",
  "auditor",
  "cluster_head",
  "store_manager",
  "tenant_admin",
  "field_officer",
];
/** Roles that review (transition) flags. */
export const FLAG_REVIEW_ROLES: ReadonlyArray<string> = [
  "owner",
  "director",
  "auditor",
  "cluster_head",
  "store_manager",
  "tenant_admin",
];

/** SPEC 6.1 state diagram (same table as apps/api/farmerapp/flags/models.py TRANSITIONS). */
export const TRANSITIONS: Readonly<Record<FlagStatus, ReadonlyArray<FlagStatus>>> = {
  open: ["in_review"],
  in_review: ["resolved_valid", "resolved_fixed", "escalated"],
  escalated: ["resolved_fixed", "resolved_action"],
  resolved_valid: [],
  resolved_fixed: [],
  resolved_action: [],
};

/** Moves that need a note (the API answers 409 `invalid_transition` / `note_required`). */
export function noteRequired(to: FlagStatus): boolean {
  return to !== "in_review";
}

export function isResolved(status: FlagStatus): boolean {
  return !UNRESOLVED_STATUSES.includes(status);
}

/**
 * Actions the detail screen offers: the server's `allowed_transitions` (empty for the
 * subject) intersected with the local state machine, so a stale or tampered list can never
 * show a move the diagram does not allow.
 */
export function availableActions(
  status: FlagStatus,
  allowed: ReadonlyArray<string> | undefined,
  role: string | undefined,
): FlagStatus[] {
  if (!role || !FLAG_REVIEW_ROLES.includes(role)) return [];
  const local = TRANSITIONS[status] ?? [];
  const server = allowed ?? local;
  return local.filter((s) => server.includes(s));
}

// ---- SLA ---------------------------------------------------------------------------------
export interface SlaState {
  /** Milliseconds until the SLA; negative when overdue. */
  remainingMs: number;
  overdue: boolean;
  /** Less than 20% of a day left (amber). */
  dueSoon: boolean;
  /** "2d 03h", "3h 05m", "4m 09s" (absolute value). */
  text: string;
}

const pad = (n: number) => String(n).padStart(2, "0");

/** Countdown text for an absolute duration in ms: days+hours, hours+minutes or minutes+seconds. */
export function formatCountdown(ms: number): string {
  const total = Math.floor(Math.abs(ms) / 1000);
  const d = Math.floor(total / 86_400);
  const h = Math.floor((total % 86_400) / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (d > 0) return `${d}d ${pad(h)}h`;
  if (h > 0) return `${h}h ${pad(m)}m`;
  return `${m}m ${pad(s)}s`;
}

export function slaState(
  slaDueAt: string,
  now: number,
  opts: { status?: FlagStatus; overdue?: boolean } = {},
): SlaState {
  const remainingMs = new Date(slaDueAt).getTime() - now;
  const resolved = opts.status ? isResolved(opts.status) : false;
  const overdue = !resolved && (remainingMs <= 0 || opts.overdue === true);
  return {
    remainingMs,
    overdue,
    dueSoon: !overdue && !resolved && remainingMs < 0.2 * 86_400_000,
    text: formatCountdown(remainingMs),
  };
}

// ---- shapes ------------------------------------------------------------------------------
export interface Flag {
  id: string;
  rule_id: string;
  rule_version: number;
  subject_type: SubjectType | string;
  subject_id: string;
  severity: FlagSeverity | string;
  title: string;
  status: FlagStatus;
  owner_id: string | null;
  owner_role: string | null;
  watchers: string[];
  sla_due_at: string;
  overdue: boolean;
  escalation_level: number;
  raised_by_mode: string;
  resolution_note: string | null;
  resolved_at: string | null;
  resolved_by: string | null;
  created_at: string;
  version: number;
}

export interface FlagCounts {
  total: number;
  by_severity: Record<string, number>;
  by_rule: Record<string, number>;
}

export interface FlagPage {
  items: Flag[];
  next_cursor?: string | null;
  counts: FlagCounts;
}

export interface EvidenceRecord {
  type: string;
  id: string;
  summary?: Record<string, unknown>;
}

export interface EvidencePhoto {
  blob_uri: string;
  signed_url?: string | null;
  signed_url_expires_at?: string | null;
}

/** GeoJSON geometries (Point: [lng, lat]; Polygon: rings of [lng, lat]). */
export interface GeoPoint {
  type: "Point";
  coordinates: [number, number];
  properties?: Record<string, unknown>;
  label?: string;
}
export interface GeoPolygon {
  type: "Polygon";
  coordinates: Array<Array<[number, number]>>;
  label?: string;
}

export interface Evidence {
  records: EvidenceRecord[];
  map: { points?: Array<Record<string, unknown>>; polygons?: Array<Record<string, unknown>> };
  photos: EvidencePhoto[];
  metrics: Record<string, unknown>;
}

export interface FlagEvent {
  id: string;
  kind: "created" | "transition" | "assigned" | "sla_escalated" | string;
  actor_id: string | null;
  from_status: string | null;
  to_status: string;
  from_owner_id: string | null;
  to_owner_id: string | null;
  label: string | null;
  note: string | null;
  created_at: string;
}

export interface FlagComment {
  id: string;
  author_id: string;
  body: string;
  is_subject_explanation: boolean;
  created_at: string;
}

export interface FlagDetail extends Flag {
  evidence: Evidence;
  events: FlagEvent[];
  comments: FlagComment[];
  allowed_transitions: FlagStatus[];
}

export interface FlagFilters {
  status?: FlagStatus[];
  severity?: FlagSeverity[];
  rule_id?: string;
  subject_type?: SubjectType;
  owner_me?: boolean;
  overdue?: boolean;
  cursor?: string | null;
  limit?: number;
}

export function flagQuery(f: FlagFilters): string {
  const p = new URLSearchParams();
  for (const s of f.status ?? []) p.append("status", s);
  for (const s of f.severity ?? []) p.append("severity", s);
  if (f.rule_id) p.set("rule_id", f.rule_id);
  if (f.subject_type) p.set("subject_type", f.subject_type);
  if (f.owner_me) p.set("owner", "me");
  if (f.overdue) p.set("overdue", "true");
  if (f.cursor) p.set("cursor", f.cursor);
  if (f.limit) p.set("limit", String(f.limit));
  const s = p.toString();
  return s ? `?${s}` : "";
}

// ---- geometry helpers --------------------------------------------------------------------
const isPair = (v: unknown): v is [number, number] =>
  Array.isArray(v) && v.length >= 2 && typeof v[0] === "number" && typeof v[1] === "number";

/** Evidence map geometries validated into points / polygons (unknown shapes are dropped). */
export function evidenceGeometry(map: Evidence["map"]): {
  points: GeoPoint[];
  polygons: GeoPolygon[];
} {
  const points: GeoPoint[] = [];
  for (const raw of map.points ?? []) {
    const coords = (raw as { coordinates?: unknown }).coordinates;
    if (isPair(coords))
      points.push({
        type: "Point",
        coordinates: [coords[0], coords[1]],
        label: typeof raw.label === "string" ? raw.label : undefined,
      });
  }
  const polygons: GeoPolygon[] = [];
  for (const raw of map.polygons ?? []) {
    const rings = (raw as { coordinates?: unknown }).coordinates;
    if (Array.isArray(rings) && rings.every((r) => Array.isArray(r) && r.every(isPair)))
      polygons.push({
        type: "Polygon",
        coordinates: rings as Array<Array<[number, number]>>,
        label: typeof raw.label === "string" ? raw.label : undefined,
      });
  }
  return { points, polygons };
}

/**
 * Console routes for evidence records. Farmer 360 (C31) and officer profile (C21) belong to
 * the analytics screens; the link is only shown for record types listed here.
 */
export const RECORD_ROUTES: Readonly<Record<string, (id: string) => string>> = {
  farmer: (id) => `/farmers/${id}`,
  user: (id) => `/field-team/${id}`,
};

export function recordHref(type: string, id: string): string | null {
  const route = RECORD_ROUTES[type];
  return route ? route(id) : null;
}

// ---- calls -------------------------------------------------------------------------------
export const flagsApi = {
  list: (f: FlagFilters) => authedFetch<FlagPage>(`v1/flags${flagQuery(f)}`),
  get: (id: string) => authedFetch<FlagDetail>(`v1/flags/${id}`),
  transition: (id: string, to: FlagStatus, note: string | null) =>
    authedFetch<FlagDetail>(`v1/flags/${id}/transition`, { body: { to, note } }),
  comment: (id: string, body: string) =>
    authedFetch<FlagComment>(`v1/flags/${id}/comments`, { body: { body } }),
  assign: (id: string, userId: string, note: string | null) =>
    authedFetch<FlagDetail>(`v1/flags/${id}/assign`, { body: { user_id: userId, note } }),
};
