import { NextResponse, type NextRequest } from "next/server";
import type { TokenResponse } from "@/lib/api";
import {
  REFRESH_COOKIE,
  problemJson,
  refreshCookieOptions,
  upstreamApiBase,
} from "@/lib/server/session-cookie";

/**
 * POST: rotate the refresh token from the cookie against /v1/auth/refresh and return a fresh
 * access token + profile. The rotated refresh token goes back into the cookie only.
 */
export async function POST(req: NextRequest) {
  const token = req.cookies.get(REFRESH_COOKIE)?.value;
  if (!token) return problemJson(401, "unauthenticated", "No session");

  let upstream: Response;
  try {
    upstream = await fetch(`${upstreamApiBase(req)}/v1/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: token }),
    });
  } catch {
    return problemJson(503, "unavailable", "API unreachable");
  }

  if (!upstream.ok) {
    const res = new NextResponse(await upstream.text(), {
      status: upstream.status,
      headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" },
    });
    res.cookies.set(REFRESH_COOKIE, "", { ...refreshCookieOptions, maxAge: 0 });
    return res;
  }

  const data = (await upstream.json()) as TokenResponse;
  const res = NextResponse.json({
    access_token: data.access_token,
    expires_in: data.expires_in,
    user: data.user,
  });
  res.cookies.set(REFRESH_COOKIE, data.refresh_token, refreshCookieOptions);
  return res;
}
