import { NextResponse, type NextRequest } from "next/server";
import {
  REFRESH_COOKIE,
  problemJson,
  refreshCookieOptions,
  upstreamApiBase,
} from "@/lib/server/session-cookie";

/** POST {refresh_token}: store it in the httpOnly cookie after a successful OTP verify. */
export async function POST(req: NextRequest) {
  const body = (await req.json().catch(() => ({}))) as { refresh_token?: unknown };
  const token = body.refresh_token;
  if (typeof token !== "string" || token.length < 16)
    return problemJson(400, "bad_request", "refresh_token is required");
  const res = NextResponse.json({ ok: true });
  res.cookies.set(REFRESH_COOKIE, token, refreshCookieOptions);
  return res;
}

/** DELETE: revoke the refresh family upstream (best effort) and clear the cookie. */
export async function DELETE(req: NextRequest) {
  const token = req.cookies.get(REFRESH_COOKIE)?.value;
  if (token) {
    await fetch(`${upstreamApiBase(req)}/v1/auth/logout`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: token }),
    }).catch(() => undefined);
  }
  const res = new NextResponse(null, { status: 204 });
  res.cookies.set(REFRESH_COOKIE, "", { ...refreshCookieOptions, maxAge: 0 });
  return res;
}
