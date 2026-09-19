/**
 * Test helper: route `fetch` to the in-app mock handlers for flags, step-up, users, settings and
 * audit logs (lib/mock/flags.ts, lib/mock/admin.ts) so hooks and screens run against the same
 * contract as Playwright, without a Next server. Records every call with its headers.
 */
import { vi } from "vitest";
import { handleAdmin, resetMockAdmin } from "@/lib/mock/admin";
import { handleCatalog, resetMockCatalog } from "@/lib/mock/catalog";
import { handleFlags, resetMockFlags } from "@/lib/mock/flags";

export interface AdminFetchLog {
  method: string;
  path: string;
  headers: Headers;
  body: Record<string, unknown>;
}

export function installAdminFetch() {
  resetMockAdmin();
  resetMockFlags();
  resetMockCatalog();
  const calls: AdminFetchLog[] = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(String(input), "http://localhost");
    const method = (init?.method ?? "GET").toUpperCase();
    const headers = new Headers(init?.headers);
    const body = init?.body ? (JSON.parse(String(init.body)) as Record<string, unknown>) : {};
    calls.push({ method, path: url.pathname + url.search, headers, body });
    if (url.pathname === "/api/session/refresh")
      return new Response(JSON.stringify({ code: "unauthenticated" }), { status: 401 });
    const path = url.pathname.replace(/^\/api\/mock\/v1\//, "").split("/");
    const m = /^Bearer mock-access-([a-z_]+)-/.exec(headers.get("authorization") ?? "");
    const actor = m?.[1] ? { id: `u-${m[1]}`, role: m[1] } : null;
    const res =
      handleFlags(method, path, url.searchParams, body, actor) ??
      handleAdmin(method, path, url.searchParams, body, actor, headers) ??
      handleCatalog(method, path, url.searchParams, body, actor);
    if (!res) return new Response("not mocked", { status: 404 });
    if (res.text !== undefined)
      return new Response(res.text, { status: res.status, headers: res.headers });
    return new Response(JSON.stringify(res.json), {
      status: res.status,
      headers: { "content-type": "application/json", ...res.headers },
    });
  });
  return { calls, spy };
}
