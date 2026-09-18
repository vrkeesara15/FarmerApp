import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, apiFetch, auth, setAuthToken } from "./api";

const jsonResponse = (body: unknown, init: ResponseInit & { type?: string } = {}) =>
  new Response(JSON.stringify(body), {
    status: init.status ?? 200,
    headers: { "content-type": init.type ?? "application/json" },
  });

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

  it("POSTs a JSON body and sends bearer token", async () => {
    const spy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(jsonResponse({ requestId: "r1", expiresInSeconds: 60 }));
    setAuthToken("tok");
    await auth.requestOtp("9876543210");
    const init = spy.mock.calls[0]![1] as RequestInit;
    expect(init.method).toBe("POST");
    expect(init.body).toBe(JSON.stringify({ phone: "+919876543210" }));
    expect(new Headers(init.headers).get("authorization")).toBe("Bearer tok");
  });

  it("throws ApiError with problem+json details", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse(
        {
          type: "https://farmerapp/errors/otp-invalid",
          title: "Invalid OTP",
          status: 401,
          detail: "Code mismatch",
          errors: { code: ["mismatch"] },
        },
        { status: 401, type: "application/problem+json" },
      ),
    );
    const err = await apiFetch("auth/otp/verify", { body: {} }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    const apiErr = err as ApiError;
    expect(apiErr.status).toBe(401);
    expect(apiErr.message).toBe("Code mismatch");
    expect(apiErr.problem.errors?.code).toEqual(["mismatch"]);
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
