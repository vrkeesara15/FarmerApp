import { NextResponse, type NextRequest } from "next/server";
import { handleAdmin, resetMockAdmin } from "@/lib/mock/admin";
import { handleAnalytics } from "@/lib/mock/analytics";
import {
  handleCatalog,
  resetMockCatalog,
  type MockActor,
  type MockResult,
} from "@/lib/mock/catalog";
import { handleFlags, resetMockFlags } from "@/lib/mock/flags";

/**
 * In-app mock of the FarmerApp API, used when NEXT_PUBLIC_API_URL is unset (dev + Playwright).
 * Mirrors apps/api/openapi.yaml shapes for the auth endpoints (FA-001): problem+json errors
 * with stable codes, 5-wrong-attempt lockout, 3 resends per 15 min. Holds no real data.
 *
 * Roles: any +91 mobile signs in as the owner except the numbers in MOCK_ROLE_BY_PHONE
 * (e.g. +919000000008 = agronomist). The role is carried in the mock tokens
 * (`mock-access-<role>-<ts>`, `mock-refresh-<role>-<ts>-<rand>`) so a refresh keeps it.
 * `/v1/catalog/*` (WC-005) is served by lib/mock/catalog.ts; `/v1/analytics/*` (M4) by
 * lib/mock/analytics.ts; `/v1/flags*` (WC-010) by lib/mock/flags.ts; `/v1/auth/step-up*`,
 * `/v1/users*`, `/v1/settings*` and `/v1/audit-logs*` (SEC-028, WC-011, WC-012, WC-103) by
 * lib/mock/admin.ts.
 */
export const MOCK_OTP = "123456";
export const MOCK_UNKNOWN_PHONE = "+919999999999";
const MAX_ATTEMPTS = 5;
const MAX_RESENDS = 3;
const WINDOW_MS = 15 * 60_000;
const LOCK_MS = 15 * 60_000;

interface PhoneState {
  attempts: number;
  sends: number[];
  lockedUntil: number;
}
const state = new Map<string, PhoneState>();

/** Test hook: forget all lockouts and resend windows and restore the seeded catalogue. */
export function resetMockState() {
  state.clear();
  resetMockCatalog();
  resetMockAdmin();
  resetMockFlags();
}

function toResponse(result: MockResult): NextResponse {
  const headers = result.headers ?? {};
  if (result.text !== undefined)
    return new NextResponse(result.text, { status: result.status, headers });
  return NextResponse.json(result.json, { status: result.status, headers });
}

/** Mock numbers that sign in with a role other than owner (docs: apps/console/README.md). */
export const MOCK_ROLE_BY_PHONE: Readonly<Record<string, string>> = {
  "+919000000002": "director",
  "+919000000003": "cluster_head",
  "+919000000004": "store_manager",
  "+919000000005": "auditor",
  "+919000000006": "accountant",
  "+919000000007": "field_officer",
  "+919000000008": "agronomist",
  "+919000000009": "tenant_admin",
};

const roleForPhone = (phone: string): string => MOCK_ROLE_BY_PHONE[phone] ?? "owner";
const phoneForRole = (role: string): string =>
  Object.entries(MOCK_ROLE_BY_PHONE).find(([, r]) => r === role)?.[0] ?? mockUser.phone;

/** `mock-access-<role>-<ts>` / `mock-refresh-<role>-...` -> role (legacy tokens = owner). */
export function roleFromToken(token: string, kind: "access" | "refresh"): string | null {
  const prefix = `mock-${kind}-`;
  if (!token.startsWith(prefix)) return null;
  const m = /^([a-z_]+)-/.exec(token.slice(prefix.length));
  return m?.[1] ?? "owner";
}

function actorFrom(req: NextRequest): MockActor | null {
  const authz = req.headers.get("authorization") ?? "";
  if (!authz.startsWith("Bearer ")) return null;
  const role = roleFromToken(authz.slice(7), "access");
  return role ? { id: `u-${role}`, role } : null;
}

function phoneState(phone: string): PhoneState {
  let s = state.get(phone);
  if (!s) {
    s = { attempts: 0, sends: [], lockedUntil: 0 };
    state.set(phone, s);
  }
  return s;
}

const mockUser = {
  id: "u1",
  tenant_id: "t1",
  phone: "+919876543210",
  name: "Suresh Patil",
  role: "owner",
  store_id: null,
  cluster_id: null,
  language: "en",
  status: "active",
};

function problem(status: number, code: string, detail?: string, extra?: Record<string, unknown>) {
  return NextResponse.json(
    { type: `https://farmerapp.dev/problems/${code}`, title: code, status, code, detail, ...extra },
    { status, headers: { "content-type": "application/problem+json" } },
  );
}

function tokens(phone: string, role: string = roleForPhone(phone)) {
  const now = Date.now();
  return {
    access_token: `mock-access-${role}-${now}`,
    refresh_token: `mock-refresh-${role}-${now}-${Math.random().toString(36).slice(2)}`,
    token_type: "Bearer",
    expires_in: 900,
    user: { ...mockUser, id: `u-${role}`, phone, role },
  };
}

async function handle(req: NextRequest, rawPath: string[]): Promise<NextResponse> {
  const path = rawPath[0] === "v1" ? rawPath.slice(1) : rawPath;
  const route = `${req.method} /${path.join("/")}`;
  const body =
    req.method === "POST" || req.method === "PUT" || req.method === "PATCH"
      ? ((await req.json().catch(() => ({}))) as Record<string, unknown>)
      : {};
  const now = Date.now();

  const catalogResult = handleCatalog(
    req.method,
    path,
    req.nextUrl.searchParams,
    body,
    actorFrom(req),
  );
  const moduleResult =
    catalogResult ??
    handleAnalytics(req.method, path, req.nextUrl.searchParams, actorFrom(req)) ??
    handleFlags(req.method, path, req.nextUrl.searchParams, body, actorFrom(req)) ??
    handleAdmin(req.method, path, req.nextUrl.searchParams, body, actorFrom(req), req.headers);
  if (moduleResult) {
    return toResponse(moduleResult);
  }

  switch (route) {
    case "GET /health":
      return NextResponse.json({ status: "ok", mock: true });

    case "POST /auth/otp/send": {
      const phone = typeof body.phone === "string" ? body.phone : "";
      if (!/^\+91[6-9]\d{9}$/.test(phone))
        return problem(422, "validation_error", "phone must be an Indian mobile number", {
          errors: [{ loc: ["body", "phone"], msg: "invalid", type: "value_error" }],
        });
      if (phone === MOCK_UNKNOWN_PHONE)
        return problem(404, "user_not_found", "No account for this number.");
      const s = phoneState(phone);
      if (s.lockedUntil > now)
        return problem(423, "otp_locked", "Too many wrong attempts.", {
          retry_after: Math.ceil((s.lockedUntil - now) / 1000),
        });
      s.sends = s.sends.filter((t) => t > now - WINDOW_MS);
      if (s.sends.length > MAX_RESENDS)
        return problem(429, "otp_rate_limited", "Too many codes requested.", {
          retry_after: Math.ceil(((s.sends[0] ?? now) + WINDOW_MS - now) / 1000),
        });
      s.sends.push(now);
      s.attempts = 0;
      return NextResponse.json(
        {
          challenge_id: `mock-${now}`,
          phone_masked: `+91******${phone.slice(-4)}`,
          channel: "sms",
          expires_in: 300,
          resend_after: 30,
          resends_left: MAX_RESENDS - (s.sends.length - 1),
        },
        { status: 202 },
      );
    }

    case "POST /auth/otp/verify": {
      const phone = typeof body.phone === "string" ? body.phone : "";
      const s = phoneState(phone);
      if (s.lockedUntil > now)
        return problem(423, "otp_locked", "Too many wrong attempts.", {
          retry_after: Math.ceil((s.lockedUntil - now) / 1000),
        });
      if (s.sends.length === 0) return problem(404, "otp_not_found", "Request a code first.");
      if (body.code !== MOCK_OTP) {
        s.attempts += 1;
        if (s.attempts >= MAX_ATTEMPTS) {
          s.lockedUntil = now + LOCK_MS;
          return problem(423, "otp_locked", "Too many wrong attempts.", {
            retry_after: LOCK_MS / 1000,
          });
        }
        return problem(401, "otp_invalid", "Incorrect code.", {
          attempts_left: MAX_ATTEMPTS - s.attempts,
        });
      }
      s.attempts = 0;
      return NextResponse.json(tokens(phone));
    }

    case "POST /auth/refresh": {
      const token = typeof body.refresh_token === "string" ? body.refresh_token : "";
      const role = roleFromToken(token, "refresh");
      if (!role) return problem(401, "refresh_invalid", "Unknown refresh token.");
      return NextResponse.json(tokens(phoneForRole(role), role));
    }

    case "POST /auth/logout":
      return new NextResponse(null, { status: 204 });

    case "GET /me": {
      const actor = actorFrom(req);
      if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
      return NextResponse.json({
        ...mockUser,
        id: actor.id,
        role: actor.role,
        phone: phoneForRole(actor.role),
      });
    }

    default:
      return problem(404, "not_found", `No mock for ${route}`);
  }
}

type Ctx = { params: Promise<{ path: string[] }> };

export async function GET(req: NextRequest, ctx: Ctx) {
  return handle(req, (await ctx.params).path);
}
export async function POST(req: NextRequest, ctx: Ctx) {
  return handle(req, (await ctx.params).path);
}
export async function PUT(req: NextRequest, ctx: Ctx) {
  return handle(req, (await ctx.params).path);
}
export async function PATCH(req: NextRequest, ctx: Ctx) {
  return handle(req, (await ctx.params).path);
}
