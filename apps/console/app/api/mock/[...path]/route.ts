import { NextResponse, type NextRequest } from "next/server";

/**
 * In-app mock of the FarmerApp API, used when NEXT_PUBLIC_API_URL is unset (dev + Playwright).
 * Errors are RFC 9457 problem+json. Not shipped behind auth — it holds no real data.
 */
const MOCK_OTP = "123456";

function problem(status: number, title: string, detail?: string, extra?: Record<string, unknown>) {
  return NextResponse.json(
    { type: "about:blank", title, status, detail, ...extra },
    { status, headers: { "content-type": "application/problem+json" } },
  );
}

async function handle(req: NextRequest, path: string[]): Promise<NextResponse> {
  const route = `${req.method} /${path.join("/")}`;
  const body =
    req.method === "POST" ? ((await req.json().catch(() => ({}))) as Record<string, unknown>) : {};

  switch (route) {
    case "GET /health":
      return NextResponse.json({ status: "ok", mock: true });

    case "POST /auth/otp/request": {
      const phone = typeof body.phone === "string" ? body.phone : "";
      if (!/^\+91[6-9]\d{9}$/.test(phone))
        return problem(422, "Validation failed", "phone must be an Indian mobile number", {
          errors: { phone: ["invalid"] },
        });
      return NextResponse.json({ requestId: `mock-${Date.now()}`, expiresInSeconds: 60 });
    }

    case "POST /auth/otp/verify": {
      if (body.code !== MOCK_OTP)
        return problem(401, "Invalid OTP", "The code did not match. Try 123456.");
      return NextResponse.json({
        accessToken: "mock-token",
        user: {
          id: "u1",
          name: "Suresh Patil",
          role: "owner",
          tenantId: "t1",
          tenantName: "Kisan Agro Centre",
        },
      });
    }

    case "GET /me":
      return NextResponse.json({
        id: "u1",
        name: "Suresh Patil",
        role: "owner",
        tenantId: "t1",
        tenantName: "Kisan Agro Centre",
      });

    default:
      return problem(404, "Not found", `No mock for ${route}`);
  }
}

type Ctx = { params: Promise<{ path: string[] }> };

export async function GET(req: NextRequest, ctx: Ctx) {
  return handle(req, (await ctx.params).path);
}
export async function POST(req: NextRequest, ctx: Ctx) {
  return handle(req, (await ctx.params).path);
}
