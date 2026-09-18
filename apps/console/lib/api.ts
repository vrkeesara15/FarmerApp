/**
 * Stub API client. Base URL comes from NEXT_PUBLIC_API_URL; when unset the in-app mock
 * (app/api/mock) is used so the console runs and the Playwright smoke test passes without
 * a backend. Errors follow RFC 9457 problem+json and are surfaced as ApiError.
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
  /** FarmerApp extension: per-field validation errors. */
  errors?: Record<string, string[]>;
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

export function setAuthToken(token: string | null): void {
  authToken = token;
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

// ---- Auth endpoints (shape to be confirmed against apps/api OpenAPI) ----

export interface OtpRequestResponse {
  requestId: string;
  expiresInSeconds: number;
}

export interface OtpVerifyResponse {
  accessToken: string;
  user: { id: string; name: string; role: string; tenantId: string; tenantName: string };
}

export const auth = {
  requestOtp: (phone: string) =>
    apiFetch<OtpRequestResponse>("auth/otp/request", { body: { phone: `+91${phone}` } }),
  verifyOtp: (requestId: string, code: string) =>
    apiFetch<OtpVerifyResponse>("auth/otp/verify", { body: { requestId, code } }),
};
