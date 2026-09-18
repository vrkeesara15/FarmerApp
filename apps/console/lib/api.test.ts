import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, apiFetch, auth, getAuthToken, session, setAuthToken } from "./api";

const jsonResponse = (body: unknown, init: ResponseInit & { type?: string } = {}) =>
  new Response(JSON.stringify(body), {
    status: init.status ?? 200,
    headers: { "content-type": init.type ?? "application/json" },
  });

const tokenResponse = {
  access_token: "acc.ess.token",
  refresh_token: "r".repeat(48),
  token_type: "Bearer" as const,
  expires_in: 900,
  user: {
    id: "u1",
    tenant_id: "t1",
    phone: "+919876543210",
    name: "Suresh",
    role: "owner",
    store_id: null,
    cluster_id: null,
    language: "en",
    status: "active" as const,
  },
};

describe("apiFetch", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    setAuthToken(null);
  });

  it("GETs JSON from the base URL", async () => {
    const spy = vi.spyOn(globalThis, "fetch").mockResolvedValue(jsonResponse({ ok: true }));
    await expect(apiFetch<{ ok: boolean }>("/health")).resolves.toEqual({ ok: true });
    const [url, init] = spy.mock.calls[0]!;
    expect(url).toBe("/api/mock/health");
    expect((init as RequestInit).method).toBe("GET");
  });

  it("sendOtp POSTs the E.164 phone to /v1/auth/otp/send", async () => {
    const spy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse(
        {
          challenge_id: "c1",
          phone_masked: "+91******3210",
          channel: "sms",
          expires_in: 300,
          resend_after: 30,
          resends_left: 3,
        },
        { status: 202 },
      ),
    );
    const res = await auth.sendOtp("9876543210");
    expect(res.resends_left).toBe(3);
    const [url, init] = spy.mock.calls[0]!;
    expect(url).toBe("/api/mock/v1/auth/otp/send");
    expect((init as RequestInit).method).toBe("POST");
    expect((init as RequestInit).body).toBe(JSON.stringify({ phone: "+919876543210" }));
  });

  it("verifyOtp POSTs phone + code and me() sends the bearer token", async () => {
    const spy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(jsonResponse(tokenResponse))
      .mockResolvedValueOnce(jsonResponse(tokenResponse.user));
    const res = await auth.verifyOtp("9876543210", "123456");
    expect(res.user.role).toBe("owner");
    expect(spy.mock.calls[0]![0]).toBe("/api/mock/v1/auth/otp/verify");
    expect(JSON.parse((spy.mock.calls[0]![1] as RequestInit).body as string)).toEqual({
      phone: "+919876543210",
      code: "123456",
      device_name: "console",
    });
    setAuthToken(res.access_token);
    await auth.me();
    const init = spy.mock.calls[1]![1] as RequestInit;
    expect(spy.mock.calls[1]![0]).toBe("/api/mock/v1/me");
    expect(new Headers(init.headers).get("authorization")).toBe("Bearer acc.ess.token");
  });

  it("throws ApiError with problem+json code and extras", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse(
        {
          type: "https://farmerapp.dev/problems/otp_locked",
          title: "Locked",
          status: 423,
          detail: "Too many wrong attempts.",
          code: "otp_locked",
          retry_after: 900,
        },
        { status: 423, type: "application/problem+json" },
      ),
    );
    const err = await apiFetch("v1/auth/otp/verify", { body: {} }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    const apiErr = err as ApiError;
    expect(apiErr.status).toBe(423);
    expect(apiErr.message).toBe("Too many wrong attempts.");
    expect(apiErr.problem.code).toBe("otp_locked");
    expect(apiErr.problem.retry_after).toBe(900);
  });

  it("wraps non-JSON failures and network errors", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("boom", { status: 500, statusText: "Server Error" }),
    );
    await expect(apiFetch("x")).rejects.toMatchObject({ status: 500, message: "Server Error" });
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new TypeError("Failed to fetch"));
    await expect(apiFetch("x")).rejects.toMatchObject({
      status: 0,
      problem: { title: "Network error" },
    });
  });
});

describe("session", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    setAuthToken(null);
  });

  it("start keeps the access token in memory and posts the refresh token to the cookie route", async () => {
    const spy = vi.spyOn(globalThis, "fetch").mockResolvedValue(jsonResponse({ ok: true }));
    await session.start(tokenResponse);
    expect(getAuthToken()).toBe("acc.ess.token");
    const [url, init] = spy.mock.calls[0]!;
    expect(url).toBe("/api/session");
    expect((init as RequestInit).method).toBe("POST");
    expect((init as RequestInit).body).toBe(
      JSON.stringify({ refresh_token: tokenResponse.refresh_token }),
    );
  });

  it("refresh rotates via the cookie route and clears the token when signed out", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      jsonResponse({ access_token: "new.access", expires_in: 900, user: tokenResponse.user }),
    );
    const res = await session.refresh();
    expect(res?.access_token).toBe("new.access");
    expect(getAuthToken()).toBe("new.access");
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      jsonResponse({ code: "unauthenticated", status: 401, title: "x" }, { status: 401 }),
    );
    expect(await session.refresh()).toBeNull();
    expect(getAuthToken()).toBeNull();
  });

  it("end forgets the token and DELETEs the cookie", async () => {
    const spy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(new Response(null, { status: 204 }));
    setAuthToken("x");
    await session.end();
    expect(getAuthToken()).toBeNull();
    expect((spy.mock.calls[0]![1] as RequestInit).method).toBe("DELETE");
  });
});
