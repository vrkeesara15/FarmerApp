/**
 * NF-013 data-principal requests (DPDP): typed client for `/v1/admin/data-requests*`.
 *
 * Staff (owner, tenant_admin) work a queue of access / correction / erasure / grievance
 * requests. Shapes mirror apps/api/openapi.yaml and are validated with zod, so a response that
 * drifts fails loudly instead of rendering `undefined`. The two destructive endpoints
 * (`apply-correction`, `erase`) are `x-step-up: true`; their headers come from `runWithStepUp`
 * (lib/step-up.ts) exactly like the WC-011 / WC-012 admin calls.
 */
import { z } from "zod";
import { authedFetch } from "./api";

type Headers = Record<string, string>;

/** `x-roles` of every `/v1/admin/data-requests*` operation. */
export const DATA_REQUEST_ROLES: ReadonlyArray<string> = ["owner", "tenant_admin"];

export const DATA_REQUEST_TYPES = ["deletion", "access", "correction", "grievance"] as const;
export type DataRequestType = (typeof DATA_REQUEST_TYPES)[number];

export const DATA_REQUEST_STATUSES = ["received", "in_progress", "completed", "rejected"] as const;
export type DataRequestStatus = (typeof DATA_REQUEST_STATUSES)[number];

/** Statuses the operator can still act on (the API answers 409 `invalid_transition` after). */
export const OPEN_STATUSES: ReadonlyArray<DataRequestStatus> = ["received", "in_progress"];

export const dataRequestSchema = z.object({
  id: z.string(),
  type: z.enum(DATA_REQUEST_TYPES),
  status: z.enum(DATA_REQUEST_STATUSES),
  user_id: z.string(),
  farmer_id: z.string().nullable(),
  reason: z.string().nullable(),
  subject: z.string().nullable(),
  requested_changes: z.record(z.string(), z.string()).nullable(),
  due_by: z.string(),
  overdue: z.boolean(),
  handled_by: z.string().nullable(),
  handled_at: z.string().nullable(),
  resolution_note: z.string().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
  version: z.number(),
});
export type DataRequest = z.infer<typeof dataRequestSchema>;

export const dataRequestPageSchema = z.object({
  items: z.array(dataRequestSchema),
  next_cursor: z.string().nullable().default(null),
});
export type DataRequestPage = z.infer<typeof dataRequestPageSchema>;

export const applyCorrectionSchema = z.object({
  applied: z.record(z.string(), z.string()),
  request: dataRequestSchema,
});
export type ApplyCorrectionResult = z.infer<typeof applyCorrectionSchema>;

export const retainedClassSchema = z.object({
  class: z.string(),
  until: z.string(),
  reason: z.string(),
});
export type RetainedClass = z.infer<typeof retainedClassSchema>;

export const erasureSchema = z.object({
  erased: z.array(z.string()),
  retained: z.array(retainedClassSchema),
  request: dataRequestSchema,
});
export type ErasureResult = z.infer<typeof erasureSchema>;

/** The export body is open by design (whatever the data principal's record holds). */
export type DataExport = Record<string, unknown>;

export interface DataRequestFilters {
  type?: DataRequestType | "";
  status?: DataRequestStatus | "";
  cursor?: string | null;
  limit?: number;
}

export function dataRequestQuery(f: DataRequestFilters): string {
  const p = new URLSearchParams();
  if (f.type) p.set("type", f.type);
  if (f.status) p.set("status", f.status);
  if (f.cursor) p.set("cursor", f.cursor);
  if (f.limit) p.set("limit", String(f.limit));
  const s = p.toString();
  return s ? `?${s}` : "";
}

/**
 * Queue order: oldest due date first, so the closest statutory deadline is on top; open
 * requests always sort above the ones already handled, and ties break on the id for stability.
 */
export function sortByDue(items: ReadonlyArray<DataRequest>): DataRequest[] {
  const openRank = (r: DataRequest) => (OPEN_STATUSES.includes(r.status) ? 0 : 1);
  return [...items].sort(
    (a, b) =>
      openRank(a) - openRank(b) || a.due_by.localeCompare(b.due_by) || a.id.localeCompare(b.id),
  );
}

/** Overdue = the API said so, or the deadline has passed while the screen stayed open. */
export function isOverdue(request: DataRequest, now: number = Date.now()): boolean {
  if (!OPEN_STATUSES.includes(request.status)) return false;
  return request.overdue || Date.parse(request.due_by) <= now;
}

/** Requested field -> value rows of a correction request, in a stable (alphabetical) order. */
export function correctionRows(
  request: Pick<DataRequest, "requested_changes">,
): Array<{ field: string; value: string }> {
  return Object.entries(request.requested_changes ?? {})
    .map(([field, value]) => ({ field, value }))
    .sort((a, b) => a.field.localeCompare(b.field));
}

/** Which actions the operator may start for a request (the API enforces the same rules). */
export function availableActions(request: DataRequest): {
  start: boolean;
  complete: boolean;
  reject: boolean;
  applyCorrection: boolean;
  erase: boolean;
  exportData: boolean;
} {
  const open = OPEN_STATUSES.includes(request.status);
  return {
    start: request.status === "received",
    complete: request.status === "in_progress",
    reject: open,
    applyCorrection: open && request.type === "correction" && correctionRows(request).length > 0,
    erase: open && request.type === "deletion",
    exportData: request.type === "access",
  };
}

/** `data-export-<id>-<yyyy-mm-dd>.json` */
export function exportFilename(id: string, now: Date = new Date()): string {
  return `data-export-${id}-${now.toISOString().slice(0, 10)}.json`;
}

const BASE = "v1/admin/data-requests";

export const dataRequestsApi = {
  list: async (f: DataRequestFilters = {}): Promise<DataRequestPage> =>
    dataRequestPageSchema.parse(await authedFetch<unknown>(`${BASE}${dataRequestQuery(f)}`)),
  update: async (
    id: string,
    body: { status: DataRequestStatus; note?: string },
  ): Promise<DataRequest> =>
    dataRequestSchema.parse(
      await authedFetch<unknown>(`${BASE}/${encodeURIComponent(id)}`, {
        method: "PATCH",
        body,
      }),
    ),
  applyCorrection: async (id: string, headers: Headers): Promise<ApplyCorrectionResult> =>
    applyCorrectionSchema.parse(
      await authedFetch<unknown>(`${BASE}/${encodeURIComponent(id)}/apply-correction`, {
        method: "POST",
        body: {},
        headers,
      }),
    ),
  erase: async (id: string, headers: Headers): Promise<ErasureResult> =>
    erasureSchema.parse(
      await authedFetch<unknown>(`${BASE}/${encodeURIComponent(id)}/erase`, {
        method: "POST",
        body: {},
        headers,
      }),
    ),
  export: (id: string): Promise<DataExport> =>
    authedFetch<DataExport>(`${BASE}/${encodeURIComponent(id)}/export`),
};
