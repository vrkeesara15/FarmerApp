/**
 * Step-up re-authentication (SEC-028). Admin actions (`x-step-up: true` in openapi.yaml) answer
 * 401 `step_up_required` without a fresh `X-Step-Up-Token`. The console then sends a code to
 * the admin's own phone (`POST /v1/auth/step-up/send`), verifies it (`POST /v1/auth/step-up`)
 * and retries the original request with the 5-minute token.
 *
 * The token lives in this module's memory only: never localStorage, sessionStorage, cookies or
 * the query cache. A reload or sign-out forgets it; it is reused until it expires.
 */
import { ApiError, authedFetch, type OtpSendResponse } from "./api";

export const STEP_UP_HEADER = "X-Step-Up-Token";

export interface StepUpTokenResponse {
  step_up_token: string;
  expires_in: number;
}

interface HeldToken {
  value: string;
  expiresAt: number;
}

let held: HeldToken | null = null;
/** Safety margin so a token about to expire is not sent. */
const SKEW_MS = 5_000;

export function getStepUpToken(now: number = Date.now()): string | null {
  if (!held) return null;
  if (held.expiresAt - SKEW_MS <= now) {
    held = null;
    return null;
  }
  return held.value;
}

export function setStepUpToken(res: StepUpTokenResponse, now: number = Date.now()): void {
  held = { value: res.step_up_token, expiresAt: now + res.expires_in * 1000 };
}

export function clearStepUpToken(): void {
  held = null;
}

/** Headers for a call that may need step-up (empty when no valid token is held). */
export function stepUpHeaders(now: number = Date.now()): Record<string, string> {
  const token = getStepUpToken(now);
  return token ? { [STEP_UP_HEADER]: token } : {};
}

export function isStepUpRequired(err: unknown): boolean {
  return err instanceof ApiError && err.status === 401 && err.problem.code === "step_up_required";
}

/** Thrown by `runWithStepUp` when the admin closes the dialog without verifying. */
export class StepUpCancelledError extends Error {
  constructor() {
    super("step_up_cancelled");
    this.name = "StepUpCancelledError";
  }
}

export const stepUpApi = {
  send: () => authedFetch<OtpSendResponse>("v1/auth/step-up/send", { method: "POST" }),
  verify: async (code: string): Promise<StepUpTokenResponse> => {
    const res = await authedFetch<StepUpTokenResponse>("v1/auth/step-up", { body: { code } });
    setStepUpToken(res);
    return res;
  },
};

/**
 * Run `call` with the held token (if any). On 401 `step_up_required` the held token is
 * dropped, `authenticate()` runs (the dialog: send + verify, resolving false on cancel) and
 * the call is retried once with the new token. Any other error is rethrown untouched.
 */
export async function runWithStepUp<T>(
  call: (headers: Record<string, string>) => Promise<T>,
  authenticate: () => Promise<boolean>,
): Promise<T> {
  try {
    return await call(stepUpHeaders());
  } catch (err) {
    if (!isStepUpRequired(err)) throw err;
    clearStepUpToken();
    const ok = await authenticate();
    if (!ok) throw new StepUpCancelledError();
    return call(stepUpHeaders());
  }
}
