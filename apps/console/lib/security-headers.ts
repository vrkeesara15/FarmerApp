/**
 * SEC-022 security headers for the console (SPEC 11.3: "output encoding in console; strict CSP").
 *
 * Pure builders, no Next imports, so they can be unit tested and used from three places:
 *   - `middleware.ts`  -> the Content-Security-Policy (needs a fresh nonce per request)
 *   - `next.config.ts` -> everything that does not depend on the request (see
 *     `staticSecurityHeaders()`); a header is set in exactly one of the two, never both.
 *   - `lib/security-headers.test.ts`
 *
 * Script policy: `script-src 'self' 'nonce-<n>' 'strict-dynamic'` — no `unsafe-inline` and no
 * `unsafe-eval` in production. The two inline bootstrap scripts of `app/layout.tsx`
 * (`themeInitScript`, `localeInitScript`) and Next's own bootstrap carry the nonce; every chunk
 * they load is trusted through `strict-dynamic`.
 *
 * Documented relaxations (kept deliberately, nothing else is relaxed):
 *   1. `style-src 'self' 'unsafe-inline'` — Recharts, Leaflet and `next/font` set inline *style
 *      attributes* on the elements they create. Style attributes cannot carry a nonce, and a
 *      nonce in `style-src` would switch the `unsafe-inline` fallback off, so the policy would
 *      break every chart and map. Inline styles cannot execute script, so this is the standard
 *      trade-off; scripts stay nonce-only.
 *   2. `img-src ... https:` — tenant branding logos (`branding.logo_blob_uri`), flag / diagnosis
 *      evidence photos (short-lived signed blob URLs) and the map tiles all come from hosts the
 *      tenant configures at runtime (`NEXT_PUBLIC_MAP_TILE_URL` overrides the OpenStreetMap
 *      default), so the host set is not fixed and cannot be enumerated here. Images cannot
 *      execute script.
 *   3. Development only: `'unsafe-eval'` in `script-src` and `ws:` in `connect-src` for the
 *      Next dev server's HMR. Never emitted when `NODE_ENV === "production"`.
 */

/** Request header the middleware uses to hand the per-request nonce to the root layout. */
export const NONCE_HEADER = "x-nonce";

export const CSP_HEADER = "Content-Security-Policy";

/** Default map tile host (lib/map-config.ts); only used to document the img-src relaxation. */
export const DEFAULT_TILE_ORIGIN = "https://tile.openstreetmap.org";

export interface SecurityHeaderOptions {
  /** Per-request base64 nonce from `generateNonce()`. */
  nonce: string;
  /** True outside production: allows the dev server's eval + websocket HMR. */
  dev?: boolean;
  /** `NEXT_PUBLIC_API_URL`; its origin is added to `connect-src` when set. */
  apiUrl?: string | null;
  /** `NEXT_PUBLIC_MAP_TILE_URL`; its origin is added to `img-src` when set. */
  tileUrl?: string | null;
}

/**
 * 16 random bytes, base64. Uses Web Crypto (`crypto.getRandomValues`), which exists in the
 * Next middleware (edge) runtime, in Node 22 and in jsdom.
 */
export function generateNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

/** Origin of an absolute URL (`https://api.example.com/v1` -> `https://api.example.com`). */
export function originOf(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    return new URL(url).origin;
  } catch {
    return null; // relative base URL (the in-app mock at /api/mock) — 'self' already covers it
  }
}

/** The CSP directives, in the order they are serialised (one place to read the policy). */
export function cspDirectives({
  nonce,
  dev = false,
  apiUrl,
  tileUrl,
}: SecurityHeaderOptions): Array<[string, string[]]> {
  const apiOrigin = originOf(apiUrl);
  const tileOrigin = originOf(tileUrl);

  const scriptSrc = ["'self'", `'nonce-${nonce}'`, "'strict-dynamic'"];
  if (dev) scriptSrc.push("'unsafe-eval'"); // Next dev server / React refresh only

  const connectSrc = ["'self'"];
  if (apiOrigin) connectSrc.push(apiOrigin);
  if (dev) connectSrc.push("ws:", "wss:");

  // See relaxation (2) in the module docstring: the image hosts are tenant-configured.
  const imgSrc = ["'self'", "data:", "blob:", "https:"];
  if (tileOrigin && !imgSrc.includes(tileOrigin)) imgSrc.push(tileOrigin);

  const directives: Array<[string, string[]]> = [
    ["default-src", ["'self'"]],
    ["base-uri", ["'self'"]],
    ["object-src", ["'none'"]],
    ["frame-ancestors", ["'none'"]],
    ["frame-src", ["'none'"]],
    ["form-action", ["'self'"]],
    ["script-src", scriptSrc],
    // See relaxation (1): inline style *attributes* from Recharts / Leaflet / next-font.
    ["style-src", ["'self'", "'unsafe-inline'"]],
    ["img-src", imgSrc],
    ["font-src", ["'self'", "data:"]],
    ["connect-src", connectSrc],
    ["media-src", ["'self'"]],
    ["manifest-src", ["'self'"]],
    ["worker-src", ["'self'", "blob:"]],
  ];
  if (!dev) directives.push(["upgrade-insecure-requests", []]);
  return directives;
}

/** The serialised `Content-Security-Policy` value. */
export function contentSecurityPolicy(options: SecurityHeaderOptions): string {
  return cspDirectives(options)
    .map(([name, values]) => (values.length ? `${name} ${values.join(" ")}` : name))
    .join("; ");
}

/**
 * Request-independent headers. Set once in `next.config.ts` `headers()` so they also cover
 * routes the middleware matcher skips (`/api/*`, `/_next/static/*`); never set in middleware.
 */
export function staticSecurityHeaders({ dev = false }: { dev?: boolean } = {}): Record<
  string,
  string
> {
  const headers: Record<string, string> = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    // Belt and braces with `frame-ancestors 'none'` for browsers without CSP level 2.
    "X-Frame-Options": "DENY",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Permissions-Policy":
      "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()",
  };
  // HSTS is meaningless (and confusing) on plain-http localhost, so it is production only.
  if (!dev) headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload";
  return headers;
}

/** Every SEC-022 header in one map (the CSP plus the static ones) — used by the unit tests. */
export function securityHeaders(options: SecurityHeaderOptions): Record<string, string> {
  return {
    [CSP_HEADER]: contentSecurityPolicy(options),
    ...staticSecurityHeaders({ dev: options.dev }),
  };
}
