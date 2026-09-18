import { NextRequest } from "next/server";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DELETE, POST } from "./route";
import { POST as REFRESH } from "./refresh/route";

const tokenBody = {
  access_token: "a.b.c",
  refresh_token: "n".repeat(48),
  token_type: "Bearer",
  expires_in: 900,
  user: { id: "u1", tenant_id: "t1", phone: "+919876543210", name: "S", role: "owner" },
};

describe("/api/session cookie routes", () => {
  afterEach(() => vi.restoreAllMocks());

  it("POST stores the refresh token in an httpOnly cookie scoped to /api/session", async () => {
    const res = await POST(
      new NextRequest("http://localhost/api/session", {
        method: "POST",
        body: JSON.stringify({ refresh_token: "r".repeat(48) }),
      }),
    );
    expect(res.status).toBe(200);
    const cookie = res.headers.get("set-cookie") ?? "";
    expect(cookie).toContain(`fa_refresh=${"r".repeat(48)}`);
    expect(cookie).toMatch(/HttpOnly/i);
    expect(cookie).toMatch(/SameSite=strict/i);
    expect(cookie).toContain("Path=/api/session");
  });

  it("POST rejects a missing token", async () => {
    const res = await POST(
      new NextRequest("http://localhost/api/session", { method: "POST", body: "{}" }),
    );
    expect(res.status).toBe(400);
  });

  it("refresh rotates upstream, returns access token only and re-sets the cookie", async () => {
    const spy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify(tokenBody), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    const res = await REFRESH(
      new NextRequest("http://localhost/api/session/refresh", {
        method: "POST",
        headers: { cookie: `fa_refresh=${"o".repeat(48)}` },
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({ access_token: "a.b.c", expires_in: 900, user: tokenBody.user });
    expect(body.refresh_token).toBeUndefined();
    expect(res.headers.get("set-cookie")).toContain(`fa_refresh=${"n".repeat(48)}`);
    expect(String(spy.mock.calls[0]![0])).toMatch(/\/v1\/auth\/refresh$/);
    expect(JSON.parse((spy.mock.calls[0]![1] as RequestInit).body as string)).toEqual({
      refresh_token: "o".repeat(48),
    });
  });

  it("refresh without a cookie is 401; upstream 401 clears the cookie", async () => {
    const none = await REFRESH(
      new NextRequest("http://localhost/api/session/refresh", { method: "POST" }),
    );
    expect(none.status).toBe(401);
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ code: "refresh_reused", status: 401, title: "x" }), {
        status: 401,
        headers: { "content-type": "application/problem+json" },
      }),
    );
    const reused = await REFRESH(
      new NextRequest("http://localhost/api/session/refresh", {
        method: "POST",
        headers: { cookie: "fa_refresh=stale" },
      }),
    );
    expect(reused.status).toBe(401);
    expect(await reused.json()).toMatchObject({ code: "refresh_reused" });
    expect(reused.headers.get("set-cookie")).toMatch(/fa_refresh=;/);
  });

  it("DELETE revokes upstream and clears the cookie", async () => {
    const spy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(new Response(null, { status: 204 }));
    const res = await DELETE(
      new NextRequest("http://localhost/api/session", {
        method: "DELETE",
        headers: { cookie: "fa_refresh=abc" },
      }),
    );
    expect(res.status).toBe(204);
    expect(String(spy.mock.calls[0]![0])).toMatch(/\/v1\/auth\/logout$/);
    expect(res.headers.get("set-cookie")).toMatch(/fa_refresh=;/);
  });
});
