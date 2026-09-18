/**
 * API client. Base URL comes from NEXT_PUBLIC_API_URL (e.g. http://localhost:8000); when unset
 * the in-app mock (app/api/mock) is used so the console runs and the Playwright smoke test
 * passes without a backend. Paths include the API version (`v1/...`). Errors follow RFC 9457
 * problem+json with a stable `code` and are surfaced as ApiError.
 *
 * Tokens (FA-001 / SEC-020): the access token (15 min) lives in memory only; the refresh token
 * (30 days, rotated) is kept in an httpOnly cookie by the Next route handlers under
 * /api/session, so it is never readable from page JavaScript after login.
 */

export const API_BASE_URL: string = (process.env.NEXT_PUBLIC_API_URL ?? "/api/mock").replace(
  /\/+$/,
  "",
);

export interface ProblemDetails {
  type?: string;
  title: string;
  status: number;
  detail?: string;
  instance?: string;
  /** Stable machine-readable code (e.g. `otp_locked`). */
  code?: string;
  /** Validation problems: `{ loc, msg, type }` per field. */
  errors?: Array<{ loc: string[]; msg?: string; type?: string }>;
  /** Seconds until a locked / rate-limited action may be retried. */
  retry_after?: number;
  /** Wrong-code attempts left before lockout. */
  attempts_left?: number;
  [key: string]: unknown;
}

export class ApiError extends Error {
  readonly status: number;
  readonly problem: ProblemDetails;

  constructor(problem: ProblemDetails) {
    super(problem.detail ?? problem.title);
    this.name = "ApiError";
    this.status = problem.status;
    this.problem = problem;
  }
}

export interface RequestOptions extends Omit<RequestInit, "body"> {
  body?: unknown;
  /** Bearer token; when omitted no Authorization header is sent. */
  token?: string;
}

let authToken: string | null = null;
let currentUser: AuthUser | null = null;

export function setAuthToken(token: string | null): void {
  authToken = token;
  if (token === null) currentUser = null;
}

/** The signed-in profile (set by `session.start` / `session.refresh`); null when signed out. */
export function getCurrentUser(): AuthUser | null {
  return currentUser;
}

export function setCurrentUser(user: AuthUser | null): void {
  currentUser = user;
}

export function getAuthToken(): string | null {
  return authToken;
}

async function parseProblem(res: Response): Promise<ProblemDetails> {
  const contentType = res.headers.get("content-type") ?? "";
  if (contentType.includes("json")) {
    try {
      const data = (await res.json()) as Partial<ProblemDetails>;
      return {
        ...data,
        title: data.title ?? res.statusText ?? "Request failed",
        status: data.status ?? res.status,
      };
    } catch {
      /* fall through */
    }
  }
  return { title: res.statusText || "Request failed", status: res.status };
}

/** fetch wrapper: JSON in/out, problem+json -> ApiError, network failure -> ApiError(status 0). */
export async function apiFetch<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { body, token, headers, ...init } = options;
  const url = path.startsWith("http") ? path : `${API_BASE_URL}/${path.replace(/^\/+/, "")}`;
  const h = new Headers(headers);
  h.set("Accept", "application/json, application/problem+json");
  if (body !== undefined) h.set("Content-Type", "application/json");
  const bearer = token ?? authToken;
  if (bearer) h.set("Authorization", `Bearer ${bearer}`);

  let res: Response;
  try {
    res = await fetch(url, {
      ...init,
      method: init.method ?? (body !== undefined ? "POST" : "GET"),
      headers: h,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (err) {
    throw new ApiError({
      type: "about:blank",
      title: "Network error",
      status: 0,
      detail: err instanceof Error ? err.message : String(err),
    });
  }

  if (!res.ok) throw new ApiError(await parseProblem(res));
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

// ---- Auth endpoints (apps/api/openapi.yaml: sendOtp, verifyOtp, refreshToken, logout, getMe) ----

export type UserRole =
  | "owner"
  | "director"
  | "cluster_head"
  | "auditor"
  | "store_manager"
  | "accountant"
  | "field_officer"
  | "agronomist"
  | "tenant_admin"
  | "farmer";

export interface AuthUser {
  id: string;
  tenant_id: string;
  phone: string;
  name: string;
  role: UserRole | string;
  store_id: string | null;
  cluster_id: string | null;
  language: string;
  status: "active" | "disabled";
}

export interface OtpSendResponse {
  challenge_id: string;
  phone_masked: string;
  channel: "sms" | "whatsapp";
  expires_in: number;
  resend_after: number;
  resends_left: number;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: "Bearer";
  expires_in: number;
  user: AuthUser;
}

/** Access token + profile as returned by the /api/session/refresh route (no refresh token). */
export interface SessionResponse {
  access_token: string;
  expires_in: number;
  user: AuthUser;
}

export const e164 = (phone10: string): string => `+91${phone10}`;

export const auth = {
  sendOtp: (phone10: string) =>
    apiFetch<OtpSendResponse>("v1/auth/otp/send", { body: { phone: e164(phone10) } }),
  verifyOtp: (phone10: string, code: string) =>
    apiFetch<TokenResponse>("v1/auth/otp/verify", {
      body: { phone: e164(phone10), code, device_name: "console" },
    }),
  me: () => apiFetch<AuthUser>("v1/me"),
};

let refreshInFlight: Promise<SessionResponse | null> | null = null;

const SESSION_HEADERS = { "Content-Type": "application/json" };

/** Browser-side session: access token in memory, refresh token in the httpOnly cookie. */
export const session = {
  /** After verifyOtp: remember the access token and hand the refresh token to the cookie route. */
  start: async (tokens: TokenResponse): Promise<void> => {
    setAuthToken(tokens.access_token);
    setCurrentUser(tokens.user);
    const res = await fetch("/api/session", {
      method: "POST",
      headers: SESSION_HEADERS,
      body: JSON.stringify({ refresh_token: tokens.refresh_token }),
    });
    if (!res.ok) throw new ApiError(await parseProblem(res));
  },
  /** Rotate via the cookie route; returns null (and clears the token) when signed out. */
  refresh: (): Promise<SessionResponse | null> => {
    // One rotation at a time: concurrent callers share the in-flight request, so a rotated
    // refresh token is never presented twice (reuse detection would revoke the family).
    refreshInFlight ??= (async () => {
      try {
        const res = await fetch("/api/session/refresh", { method: "POST" });
        if (!res.ok) {
          setAuthToken(null);
          return null;
        }
        const data = (await res.json()) as SessionResponse;
        setAuthToken(data.access_token);
        setCurrentUser(data.user);
        return data;
      } catch {
        setAuthToken(null);
        return null;
      } finally {
        refreshInFlight = null;
      }
    })();
    return refreshInFlight;
  },
  /** Revoke the refresh family server-side and forget the access token. */
  end: async (): Promise<void> => {
    setAuthToken(null);
    await fetch("/api/session", { method: "DELETE" }).catch(() => undefined);
  },
};

const AUTH_RETRY_CODES = new Set(["unauthenticated", "token_expired", "token_invalid"]);

function isAuthFailure(err: unknown): boolean {
  return (
    err instanceof ApiError &&
    err.status === 401 &&
    (err.problem.code === undefined || AUTH_RETRY_CODES.has(err.problem.code))
  );
}

/**
 * Authenticated call for the data layer: restores the access token from the refresh cookie
 * when the page was reloaded (token only lives in memory), and on a 401 rotates once and
 * retries. A second 401 surfaces as ApiError (the session is gone).
 */
export async function authedFetch<T>(path: string, options: RequestOptions = {}): Promise<T> {
  if (!getAuthToken()) await session.refresh();
  try {
    return await apiFetch<T>(path, options);
  } catch (err) {
    if (!isAuthFailure(err)) throw err;
    const renewed = await session.refresh();
    if (!renewed) throw err;
    return apiFetch<T>(path, options);
  }
}

/** Like authedFetch but returns the raw body as text (CSV exports). */
export async function authedFetchText(path: string): Promise<string> {
  const once = async (): Promise<Response> => {
    const token = getAuthToken();
    const url = `${API_BASE_URL}/${path.replace(/^\/+/, "")}`;
    return fetch(url, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  };
  if (!getAuthToken()) await session.refresh();
  let res = await once();
  if (res.status === 401 && (await session.refresh())) res = await once();
  if (!res.ok) throw new ApiError(await parseProblem(res));
  return res.text();
}
