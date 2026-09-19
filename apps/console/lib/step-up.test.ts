import { afterEach, describe, expect, it, vi } from "vitest";
import { installAdminFetch } from "@/test/mock-admin-fetch";
import { ApiError, setAuthToken, setCurrentUser } from "./api";
import { adminApi } from "./admin";
import {
  STEP_UP_HEADER,
  StepUpCancelledError,
  clearStepUpToken,
  getStepUpToken,
  isStepUpRequired,
  runWithStepUp,
  setStepUpToken,
  stepUpApi,
  stepUpHeaders,
} from "./step-up";

function signIn(role: string) {
  setAuthToken(`mock-access-${role}-1`);
  setCurrentUser({
    id: `u-${role}`,
    tenant_id: "t1",
    phone: "+919876543210",
    name: "Test",
    role,
    store_id: null,
    cluster_id: null,
    language: "en",
    status: "active",
  });
}

afterEach(() => {
  vi.restoreAllMocks();
  clearStepUpToken();
  setAuthToken(null);
  localStorage.clear();
  sessionStorage.clear();
});

describe("step-up token (SEC-028)", () => {
  it("is held in memory until it expires", () => {
    setStepUpToken({ step_up_token: "tok", expires_in: 300 }, 1_000);
    expect(getStepUpToken(1_000)).toBe("tok");
    expect(stepUpHeaders(1_000)).toEqual({ [STEP_UP_HEADER]: "tok" });
    // Within the 5 s safety margin the token is no longer sent.
    expect(getStepUpToken(1_000 + 296_000)).toBeNull();
    expect(stepUpHeaders(1_000 + 296_000)).toEqual({});
  });

  it("recognises only 401 step_up_required", () => {
    expect(
      isStepUpRequired(new ApiError({ title: "x", status: 401, code: "step_up_required" })),
    ).toBe(true);
    expect(isStepUpRequired(new ApiError({ title: "x", status: 401, code: "token_expired" }))).toBe(
      false,
    );
    expect(isStepUpRequired(new ApiError({ title: "x", status: 403, code: "forbidden" }))).toBe(
      false,
    );
  });
});

describe("runWithStepUp against the mock API", () => {
  it("retries the original request with X-Step-Up-Token after the OTP", async () => {
    const { calls } = installAdminFetch();
    signIn("owner");
    const authenticate = vi.fn(async () => {
      await stepUpApi.send();
      await stepUpApi.verify("123456");
      return true;
    });
    const res = await runWithStepUp(
      (h) => adminApi.forceLogout("u-field_officer", h),
      authenticate,
    );
    expect(res.revoked_sessions).toBe(2);
    expect(authenticate).toHaveBeenCalledTimes(1);
    const attempts = calls.filter((c) => c.path.endsWith("/force-logout"));
    expect(attempts).toHaveLength(2);
    expect(attempts[0]?.headers.get(STEP_UP_HEADER)).toBeNull();
    expect(attempts[1]?.headers.get(STEP_UP_HEADER)).toMatch(/^mock-stepup-/);
    expect(calls.map((c) => c.path)).toContain("/api/mock/v1/auth/step-up/send");
  });

  it("reuses the held token for the next admin action without a new OTP", async () => {
    installAdminFetch();
    signIn("owner");
    const authenticate = vi.fn(async () => {
      await stepUpApi.send();
      await stepUpApi.verify("123456");
      return true;
    });
    await runWithStepUp((h) => adminApi.forceLogout("u-field_officer", h), authenticate);
    await runWithStepUp((h) => adminApi.forceLogout("u-store_manager", h), authenticate);
    expect(authenticate).toHaveBeenCalledTimes(1);
  });

  it("never persists the token in web storage or cookies", async () => {
    installAdminFetch();
    signIn("owner");
    await runWithStepUp(
      (h) => adminApi.forceLogout("u-field_officer", h),
      async () => {
        await stepUpApi.send();
        await stepUpApi.verify("123456");
        return true;
      },
    );
    const token = getStepUpToken();
    expect(token).toMatch(/^mock-stepup-/);
    const stored = [
      ...Object.keys(localStorage).map((k) => localStorage.getItem(k)),
      ...Object.keys(sessionStorage).map((k) => sessionStorage.getItem(k)),
      document.cookie,
    ].join("|");
    expect(stored).not.toContain(token ?? "never");
  });

  it("rejects with StepUpCancelledError when the dialog is closed", async () => {
    const { calls } = installAdminFetch();
    signIn("owner");
    await expect(
      runWithStepUp(
        (h) => adminApi.forceLogout("u-field_officer", h),
        async () => false,
      ),
    ).rejects.toBeInstanceOf(StepUpCancelledError);
    expect(calls.filter((c) => c.path.endsWith("/force-logout"))).toHaveLength(1);
  });

  it("does not ask for a code when the role is not allowed (403 stays 403)", async () => {
    installAdminFetch();
    signIn("auditor");
    const authenticate = vi.fn(async () => true);
    await expect(
      runWithStepUp((h) => adminApi.forceLogout("u-field_officer", h), authenticate),
    ).rejects.toMatchObject({ status: 403 });
    expect(authenticate).not.toHaveBeenCalled();
  });

  it("drops an expired or rejected token and asks again", async () => {
    installAdminFetch();
    signIn("owner");
    setStepUpToken({ step_up_token: "mock-stepup-forged", expires_in: 300 });
    const authenticate = vi.fn(async () => {
      await stepUpApi.send();
      await stepUpApi.verify("123456");
      return true;
    });
    await runWithStepUp((h) => adminApi.forceLogout("u-field_officer", h), authenticate);
    expect(authenticate).toHaveBeenCalledTimes(1);
    expect(getStepUpToken()).not.toBe("mock-stepup-forged");
  });

  it("surfaces a wrong code as otp_invalid with attempts left", async () => {
    installAdminFetch();
    signIn("owner");
    await stepUpApi.send();
    await expect(stepUpApi.verify("000000")).rejects.toMatchObject({
      status: 401,
      problem: { code: "otp_invalid", attempts_left: 4 },
    });
    expect(getStepUpToken()).toBeNull();
  });
});
