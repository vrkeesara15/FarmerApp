import { describe, expect, it } from "vitest";
import {
  CSP_HEADER,
  NONCE_HEADER,
  contentSecurityPolicy,
  cspDirectives,
  generateNonce,
  originOf,
  securityHeaders,
  staticSecurityHeaders,
} from "./security-headers";

const directive = (csp: string, name: string): string | undefined =>
  csp
    .split("; ")
    .find((d) => d === name || d.startsWith(`${name} `))
    ?.slice(name.length)
    .trim();

const NONCE = "dGVzdC1ub25jZS0xMjM0";

describe("SEC-022 nonce", () => {
  it("is base64 and unique per call", () => {
    const a = generateNonce();
    const b = generateNonce();
    expect(a).not.toBe(b);
    expect(a).toMatch(/^[A-Za-z0-9+/]+={0,2}$/);
    // 16 random bytes -> 24 base64 characters; long enough to be unguessable.
    expect(a).toHaveLength(24);
    expect(new Set(Array.from({ length: 50 }, generateNonce)).size).toBe(50);
  });
});

describe("SEC-022 content security policy", () => {
  const csp = contentSecurityPolicy({ nonce: NONCE });

  it("allows scripts only through the nonce — never unsafe-inline or unsafe-eval", () => {
    const scriptSrc = directive(csp, "script-src");
    expect(scriptSrc).toBe(`'self' 'nonce-${NONCE}' 'strict-dynamic'`);
    expect(scriptSrc).not.toContain("unsafe-inline");
    expect(csp).not.toContain("'unsafe-eval'");
    // The only `unsafe-inline` in the whole policy is the documented style-src exception.
    expect(csp.match(/'unsafe-inline'/g)).toHaveLength(1);
  });

  it("keeps the style-src unsafe-inline fallback usable (no nonce in style-src)", () => {
    // A nonce in style-src would switch `unsafe-inline` off and break Recharts / Leaflet.
    expect(directive(csp, "style-src")).toBe("'self' 'unsafe-inline'");
  });

  it("locks framing, bases, forms, objects and plain http down", () => {
    expect(directive(csp, "frame-ancestors")).toBe("'none'");
    expect(directive(csp, "frame-src")).toBe("'none'");
    expect(directive(csp, "object-src")).toBe("'none'");
    expect(directive(csp, "base-uri")).toBe("'self'");
    expect(directive(csp, "form-action")).toBe("'self'");
    expect(directive(csp, "default-src")).toBe("'self'");
    expect(directive(csp, "font-src")).toBe("'self' data:");
    expect(csp.endsWith("upgrade-insecure-requests")).toBe(true);
  });

  it("adds the API origin to connect-src only when NEXT_PUBLIC_API_URL is absolute", () => {
    expect(directive(csp, "connect-src")).toBe("'self'");
    const withApi = contentSecurityPolicy({
      nonce: NONCE,
      apiUrl: "https://api.farmerapp.example/v1/",
    });
    expect(directive(withApi, "connect-src")).toBe("'self' https://api.farmerapp.example");
    // The in-app mock is a relative base URL: 'self' already covers it.
    const withMock = contentSecurityPolicy({ nonce: NONCE, apiUrl: "/api/mock" });
    expect(directive(withMock, "connect-src")).toBe("'self'");
  });

  it("keeps the documented img-src relaxation and names the configured tile host", () => {
    expect(directive(csp, "img-src")).toBe("'self' data: blob: https:");
    const withTiles = contentSecurityPolicy({
      nonce: NONCE,
      tileUrl: "https://tiles.internal.example/{z}/{x}/{y}.png",
    });
    expect(directive(withTiles, "img-src")).toContain("https://tiles.internal.example");
  });

  it("relaxes only eval and websockets in development, and drops the https upgrade", () => {
    const dev = contentSecurityPolicy({ nonce: NONCE, dev: true });
    expect(directive(dev, "script-src")).toContain("'unsafe-eval'");
    expect(directive(dev, "connect-src")).toBe("'self' ws: wss:");
    expect(dev).not.toContain("upgrade-insecure-requests");
  });

  it("serialises every directive exactly once", () => {
    const names = cspDirectives({ nonce: NONCE }).map(([name]) => name);
    expect(new Set(names).size).toBe(names.length);
    expect(csp.split("; ")).toHaveLength(names.length);
  });
});

describe("SEC-022 static headers", () => {
  it("sets every required header", () => {
    const headers = staticSecurityHeaders();
    expect(headers).toMatchObject({
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      "X-Frame-Options": "DENY",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
    });
    for (const feature of ["camera", "microphone", "geolocation", "payment", "usb"])
      expect(headers["Permissions-Policy"]).toContain(`${feature}=()`);
    expect(headers["Permissions-Policy"]).toContain("interest-cohort=()");
  });

  it("omits HSTS on plain-http local development", () => {
    expect(staticSecurityHeaders({ dev: true })).not.toHaveProperty("Strict-Transport-Security");
  });

  it("securityHeaders() carries the CSP plus the static set, and none of them twice", () => {
    const all = securityHeaders({ nonce: NONCE });
    expect(Object.keys(all)).toEqual([CSP_HEADER, ...Object.keys(staticSecurityHeaders())]);
    expect(all[CSP_HEADER]).toContain(`'nonce-${NONCE}'`);
    expect(NONCE_HEADER).toBe("x-nonce");
  });
});

describe("originOf", () => {
  it("reduces an absolute URL to its origin and ignores relative ones", () => {
    expect(originOf("https://api.example.com:8443/v1?x=1")).toBe("https://api.example.com:8443");
    expect(originOf("http://localhost:8000")).toBe("http://localhost:8000");
    expect(originOf("/api/mock")).toBeNull();
    expect(originOf("")).toBeNull();
    expect(originOf(undefined)).toBeNull();
  });
});
