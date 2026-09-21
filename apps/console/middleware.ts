import { NextResponse, type NextRequest } from "next/server";
import {
  CSP_HEADER,
  NONCE_HEADER,
  contentSecurityPolicy,
  generateNonce,
} from "@/lib/security-headers";

/**
 * SEC-022: the strict Content-Security-Policy. It is built per request because `script-src`
 * carries a fresh nonce (no `unsafe-inline`, no `unsafe-eval`) — see lib/security-headers.ts
 * for the policy itself and the two documented relaxations.
 *
 * The CSP is set on both
 *   - the *forwarded request* headers, which is how Next detects a nonce and stamps it on its
 *     own inline bootstrap scripts (`app/layout.tsx` reads it back from `x-nonce` for the theme
 *     and locale init scripts), and
 *   - the *response* headers, which is what the browser enforces.
 *
 * Every other SEC-022 header is request-independent and set once in `next.config.ts`
 * `headers()` (so it also covers `/api/*` and `/_next/static/*`); nothing is set twice.
 */
export function middleware(request: NextRequest): NextResponse {
  const nonce = generateNonce();
  const csp = contentSecurityPolicy({
    nonce,
    dev: process.env.NODE_ENV !== "production",
    apiUrl: process.env.NEXT_PUBLIC_API_URL,
    tileUrl: process.env.NEXT_PUBLIC_MAP_TILE_URL,
  });

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(NONCE_HEADER, nonce);
  requestHeaders.set(CSP_HEADER, csp);

  const response = NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set(CSP_HEADER, csp);
  return response;
}

export const config = {
  matcher: [
    {
      // Documents and route handlers under /api keep their own responses; static assets and
      // the image optimiser never execute script, so they only need the static headers.
      source:
        "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:png|svg|jpg|jpeg|gif|webp|ico)$).*)",
      // Prefetches reuse the cached RSC payload, so giving them a second nonce would make the
      // served HTML and the enforced policy disagree (Next's documented middleware matcher).
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" },
      ],
    },
  ],
};
