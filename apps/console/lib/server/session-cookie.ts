/**
 * Server-only helpers for the refresh-token cookie (used by app/api/session/*).
 *
 * The cookie is httpOnly + SameSite=Strict and scoped to /api/session, so page scripts never
 * see the refresh token and it is only sent to the two routes that need it.
 */
import type { NextRequest } from "next/server";

export const REFRESH_COOKIE = "fa_refresh";
const THIRTY_DAYS = 30 * 24 * 60 * 60;

export const refreshCookieOptions = {
  httpOnly: true,
  sameSite: "strict" as const,
  secure: process.env.NODE_ENV === "production",
  path: "/api/session",
  maxAge: THIRTY_DAYS,
};

/** Upstream FarmerApp API base for server-side calls (falls back to the in-app mock). */
export function upstreamApiBase(req: NextRequest): string {
  const configured = process.env.API_URL ?? process.env.NEXT_PUBLIC_API_URL;
  if (configured) return configured.replace(/\/+$/, "");
  return new URL("/api/mock", req.nextUrl.origin).toString().replace(/\/+$/, "");
}

export function problemJson(status: number, code: string, detail?: string): Response {
  return new Response(JSON.stringify({ type: `about:blank`, title: code, status, code, detail }), {
    status,
    headers: { "content-type": "application/problem+json" },
  });
}
