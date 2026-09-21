import { afterEach, describe, expect, it, vi } from "vitest";
import { installAdminFetch } from "@/test/mock-admin-fetch";
import { ApiError, setAuthToken } from "./api";
import {
  DATA_REQUEST_ROLES,
  availableActions,
  correctionRows,
  dataRequestQuery,
  dataRequestSchema,
  dataRequestsApi,
  exportFilename,
  isOverdue,
  sortByDue,
  type DataRequest,
} from "./data-requests";
import { STEP_UP_HEADER, clearStepUpToken, stepUpApi } from "./step-up";

const base: DataRequest = {
  id: "dr-x",
  type: "grievance",
  status: "received",
  user_id: "u-1",
  farmer_id: null,
  reason: null,
  subject: null,
  requested_changes: null,
  due_by: "2026-10-01T00:00:00Z",
  overdue: false,
  handled_by: null,
  handled_at: null,
  resolution_note: null,
  created_at: "2026-09-01T00:00:00Z",
  updated_at: "2026-09-01T00:00:00Z",
  version: 1,
};
const make = (over: Partial<DataRequest>): DataRequest => ({ ...base, ...over });

afterEach(() => {
  vi.restoreAllMocks();
  setAuthToken(null);
  clearStepUpToken();
});

describe("NF-013 query and ordering", () => {
  it("builds the filter query and omits empty filters", () => {
    expect(dataRequestQuery({})).toBe("");
    expect(dataRequestQuery({ type: "", status: "" })).toBe("");
    expect(dataRequestQuery({ type: "deletion", status: "received", limit: 100 })).toBe(
      "?type=deletion&status=received&limit=100",
    );
    expect(dataRequestQuery({ cursor: "50" })).toBe("?cursor=50");
  });

  it("puts the closest deadline first and the closed requests last", () => {
    const rows = sortByDue([
      make({ id: "c", status: "completed", due_by: "2026-01-01T00:00:00Z" }),
      make({ id: "b", due_by: "2026-10-05T00:00:00Z" }),
      make({ id: "a", due_by: "2026-09-20T00:00:00Z" }),
    ]);
    expect(rows.map((r) => r.id)).toEqual(["a", "b", "c"]);
  });

  it("treats a passed deadline as overdue, but never a closed request", () => {
    const now = Date.parse("2026-10-02T00:00:00Z");
    expect(isOverdue(make({}), now)).toBe(true);
    expect(isOverdue(make({ due_by: "2026-11-01T00:00:00Z" }), now)).toBe(false);
    // The API's own flag wins even before the clock catches up.
    expect(isOverdue(make({ due_by: "2026-11-01T00:00:00Z", overdue: true }), now)).toBe(true);
    expect(isOverdue(make({ status: "completed" }), now)).toBe(false);
    expect(isOverdue(make({ status: "rejected" }), now)).toBe(false);
  });
});

describe("NF-013 per-request actions", () => {
  it("lists the requested corrections alphabetically", () => {
    expect(correctionRows({ requested_changes: { village: "Kothapally", name: "Imran" } })).toEqual(
      [
        { field: "name", value: "Imran" },
        { field: "village", value: "Kothapally" },
      ],
    );
    expect(correctionRows({ requested_changes: null })).toEqual([]);
  });

  it("offers start only on a received request and complete only in progress", () => {
    expect(availableActions(make({ status: "received" }))).toMatchObject({
      start: true,
      complete: false,
      reject: true,
    });
    expect(availableActions(make({ status: "in_progress" }))).toMatchObject({
      start: false,
      complete: true,
      reject: true,
    });
    for (const status of ["completed", "rejected"] as const)
      expect(availableActions(make({ status }))).toMatchObject({
        start: false,
        complete: false,
        reject: false,
      });
  });

  it("offers erasure, correction and export only for the matching type", () => {
    expect(availableActions(make({ type: "deletion" })).erase).toBe(true);
    expect(availableActions(make({ type: "access" })).erase).toBe(false);
    expect(availableActions(make({ type: "access" })).exportData).toBe(true);
    // A correction with nothing to change cannot be applied.
    expect(availableActions(make({ type: "correction" })).applyCorrection).toBe(false);
    expect(
      availableActions(make({ type: "correction", requested_changes: { name: "Imran" } }))
        .applyCorrection,
    ).toBe(true);
    // A closed correction is read-only, whatever it asked for.
    expect(
      availableActions(
        make({ type: "correction", status: "completed", requested_changes: { name: "I" } }),
      ).applyCorrection,
    ).toBe(false);
  });

  it("names the export file after the request and the day", () => {
    expect(exportFilename("dr-0002", new Date("2026-09-19T10:00:00Z"))).toBe(
      "data-export-dr-0002-2026-09-19.json",
    );
  });
});

describe("NF-013 client against the mock API", () => {
  const signIn = (role: string) => setAuthToken(`mock-access-${role}-1`);

  it("lists the queue, validates the shape and filters by type and status", async () => {
    const { calls } = installAdminFetch();
    signIn("owner");
    const page = await dataRequestsApi.list({});
    expect(page.items.length).toBeGreaterThanOrEqual(6);
    expect(page.next_cursor).toBeNull();
    for (const item of page.items) expect(() => dataRequestSchema.parse(item)).not.toThrow();
    // The API orders by deadline; the screen then floats the open ones to the top.
    const due = page.items.map((r) => r.due_by);
    expect([...due].sort()).toEqual(due);
    const queue = sortByDue(page.items);
    expect(queue[0]?.id).toBe("dr-0001");
    expect(queue[0]?.overdue).toBe(true); // derived server-side from the deadline
    expect(queue.slice(-2).map((r) => r.status)).toEqual(["rejected", "completed"]);

    const deletions = await dataRequestsApi.list({ type: "deletion" });
    expect(deletions.items.map((r) => r.type)).toEqual(["deletion"]);
    const open = await dataRequestsApi.list({ status: "received" });
    expect(open.items.every((r) => r.status === "received")).toBe(true);
    expect(calls.at(-1)?.path).toContain("status=received");
  });

  it("refuses every role outside the NF-013 list", async () => {
    installAdminFetch();
    expect(DATA_REQUEST_ROLES).toEqual(["owner", "tenant_admin"]);
    for (const role of ["director", "auditor", "cluster_head", "field_officer"]) {
      signIn(role);
      const err = await dataRequestsApi.list({}).catch((e: unknown) => e);
      expect(err).toBeInstanceOf(ApiError);
      expect((err as ApiError).status).toBe(403);
      expect((err as ApiError).problem.code).toBe("forbidden");
    }
  });

  it("moves a request received -> in progress -> completed and rejects illegal moves", async () => {
    installAdminFetch();
    signIn("tenant_admin");
    const started = await dataRequestsApi.update("dr-0004", { status: "in_progress" });
    expect(started.status).toBe("in_progress");
    expect(started.version).toBe(2);
    const done = await dataRequestsApi.update("dr-0004", {
      status: "completed",
      note: "Consent withdrawal honoured; sender list cleaned.",
    });
    expect(done.status).toBe("completed");
    expect(done.resolution_note).toContain("Consent withdrawal");

    const err = await dataRequestsApi
      .update("dr-0004", { status: "in_progress" })
      .catch((e: unknown) => e);
    expect((err as ApiError).status).toBe(409);
    expect((err as ApiError).problem.code).toBe("invalid_transition");
  });

  it("apply-correction and erase need a step-up token, then answer with their report", async () => {
    const { calls } = installAdminFetch();
    signIn("owner");

    const needsStepUp = await dataRequestsApi
      .applyCorrection("dr-0003", {})
      .catch((e: unknown) => e);
    expect((needsStepUp as ApiError).status).toBe(401);
    expect((needsStepUp as ApiError).problem.code).toBe("step_up_required");

    await stepUpApi.send();
    const { step_up_token: token } = await stepUpApi.verify("123456");
    const headers = { [STEP_UP_HEADER]: token };

    const corrected = await dataRequestsApi.applyCorrection("dr-0003", headers);
    expect(corrected.applied).toEqual({
      name: "Imran Shaikh",
      village: "Kothapally",
      phone: "+919000000123",
    });
    expect(corrected.request.status).toBe("completed");
    expect(calls.at(-1)?.headers.get(STEP_UP_HEADER)).toBe(token);

    const erasure = await dataRequestsApi.erase("dr-0001", headers);
    expect(erasure.erased).toContain("farmer_profile");
    // NF-013: the books stay, and the operator can see why.
    const financial = erasure.retained.find((r) => r.class === "financial_records");
    expect(financial?.reason).toContain("8 financial years");
    expect(Date.parse(financial?.until ?? "")).toBeGreaterThan(Date.now());
    expect(erasure.request.status).toBe("completed");

    // Wrong type, and a closed request, are 409 invalid_transition.
    const wrongType = await dataRequestsApi.erase("dr-0002", headers).catch((e: unknown) => e);
    expect((wrongType as ApiError).status).toBe(409);
    const closed = await dataRequestsApi.erase("dr-0001", headers).catch((e: unknown) => e);
    expect((closed as ApiError).status).toBe(409);
  });

  it("returns the data principal's export as a JSON object", async () => {
    installAdminFetch();
    signIn("owner");
    const data = await dataRequestsApi.export("dr-0002");
    expect(Object.keys(data)).toEqual(
      expect.arrayContaining(["data_principal", "consents", "orders", "visits"]),
    );
    expect(JSON.stringify(data, null, 2)).toContain("data_principal");
  });
});
