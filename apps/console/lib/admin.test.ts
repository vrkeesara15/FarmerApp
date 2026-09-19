import { describe, expect, it } from "vitest";
import {
  auditDiff,
  auditQuery,
  deviceSummary,
  diffValue,
  patchNeedsStepUp,
  type Device,
} from "./admin";

describe("audit diff", () => {
  it("lists changed fields first, then unchanged ones", () => {
    const rows = auditDiff(
      { status: "active", name: "Ravi", store_id: null, role: "field_officer" },
      { status: "disabled", name: "Ravi", store_id: "s1", role: "field_officer" },
    );
    expect(rows.map((r) => [r.field, r.changed])).toEqual([
      ["status", true],
      ["store_id", true],
      ["name", false],
      ["role", false],
    ]);
  });

  it("handles creates, deletes and nested values", () => {
    expect(auditDiff(null, { a: 1 })).toEqual([
      { field: "a", before: undefined, after: 1, changed: true },
    ]);
    expect(auditDiff({ a: 1 }, null)).toEqual([
      { field: "a", before: 1, after: undefined, changed: true },
    ]);
    const nested = auditDiff({ sampling: { moving_s: 120 } }, { sampling: { moving_s: 60 } });
    expect(nested[0]?.changed).toBe(true);
    expect(diffValue({ moving_s: 60 })).toBe('{"moving_s":60}');
    expect(diffValue("x")).toBe("x");
    expect(diffValue(null)).toBe("null");
    expect(diffValue(undefined)).toBeUndefined();
  });

  it("builds the filter query (export has no paging)", () => {
    const f = {
      entity: "tenant",
      action: "tenant_settings.update",
      q: " ab12 ",
      cursor: "50",
      limit: 50,
    };
    expect(auditQuery(f)).toBe(
      "?entity=tenant&action=tenant_settings.update&q=ab12&cursor=50&limit=50",
    );
    expect(auditQuery(f, { paging: false })).toBe(
      "?entity=tenant&action=tenant_settings.update&q=ab12",
    );
  });
});

describe("users helpers", () => {
  it("needs step-up only for role / status changes", () => {
    expect(patchNeedsStepUp({ name: "x" })).toBe(false);
    expect(patchNeedsStepUp({ store_id: null })).toBe(false);
    expect(patchNeedsStepUp({ role: "auditor" })).toBe(true);
    expect(patchNeedsStepUp({ status: "disabled" })).toBe(true);
  });

  it("summarises devices, pending first", () => {
    const d = (status: Device["status"]) => ({ status }) as Device;
    expect(deviceSummary([d("active"), d("pending")])).toBe("pending");
    expect(deviceSummary([d("revoked"), d("active")])).toBe("active");
    expect(deviceSummary([d("lost")])).toBe("lost");
    expect(deviceSummary([d("revoked")])).toBe("revoked");
    expect(deviceSummary([])).toBe("none");
  });
});
