import { NextResponse, type NextRequest } from "next/server";

/**
 * In-app mock of the FarmerApp API, used when NEXT_PUBLIC_API_URL is unset (dev + Playwright).
 * Mirrors apps/api/openapi.yaml shapes for the auth endpoints (FA-001): problem+json errors
 * with stable codes, 5-wrong-attempt lockout, 3 resends per 15 min. Holds no real data.
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

/** Test hook: forget all lockouts and resend windows. */
export function resetMockState() {
  state.clear();
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

function tokens(phone: string) {
  const now = Date.now();
  return {
    access_token: `mock-access-${now}`,
    refresh_token: `mock-refresh-${now}-${Math.random().toString(36).slice(2)}`,
    token_type: "Bearer",
    expires_in: 900,
    user: { ...mockUser, phone },
  };
}

async function handle(req: NextRequest, rawPath: string[]): Promise<NextResponse> {
  const path = rawPath[0] === "v1" ? rawPath.slice(1) : rawPath;
  const route = `${req.method} /${path.join("/")}`;
  const body =
    req.method === "POST" ? ((await req.json().catch(() => ({}))) as Record<string, unknown>) : {};
  const now = Date.now();

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
      if (!token.startsWith("mock-refresh-"))
        return problem(401, "refresh_invalid", "Unknown refresh token.");
      return NextResponse.json(tokens(mockUser.phone));
    }

    case "POST /auth/logout":
      return new NextResponse(null, { status: 204 });

    case "GET /me": {
      const authz = req.headers.get("authorization") ?? "";
      if (!authz.startsWith("Bearer mock-access-"))
        return problem(401, "unauthenticated", "Bearer token required.");
      return NextResponse.json(mockUser);
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
