/**
 * Test helper: route `fetch` to the in-app mock catalogue (lib/mock/catalog.ts) so hooks and
 * screens run against the same contract as Playwright, without a Next server.
 */
import { vi } from "vitest";
import { handleCatalog, resetMockCatalog } from "@/lib/mock/catalog";

export interface FetchLog {
  method: string;
  path: string;
  authorization: string | null;
}

export function installCatalogFetch(opts: { refreshRole?: string | null } = {}) {
  resetMockCatalog();
  const calls: FetchLog[] = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(String(input), "http://localhost");
    const method = (init?.method ?? "GET").toUpperCase();
    const headers = new Headers(init?.headers);
    const authorization = headers.get("authorization");
    calls.push({ method, path: url.pathname + url.search, authorization });
    if (url.pathname === "/api/session/refresh") {
      const role = opts.refreshRole;
      if (!role) return new Response(JSON.stringify({ code: "unauthenticated" }), { status: 401 });
      return Response.json({
        access_token: `mock-access-${role}-refreshed`,
        expires_in: 900,
        user: {
          id: `u-${role}`,
          name: "Test User",
          role,
          tenant_id: "t1",
          phone: "+919000000000",
          store_id: null,
          cluster_id: null,
          language: "en",
          status: "active",
        },
      });
    }
    const path = url.pathname.replace(/^\/api\/mock\/v1\//, "").split("/");
    const m = /^Bearer mock-access-([a-z_]+)-/.exec(authorization ?? "");
    const body = init?.body ? (JSON.parse(String(init.body)) as Record<string, unknown>) : {};
    const res = handleCatalog(
      method,
      path,
      url.searchParams,
      body,
      m?.[1] ? { id: `u-${m[1]}`, role: m[1] } : null,
    );
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
