import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { getAuthToken, setAuthToken } from "@/lib/api";
import { LoginForm, loginErrorMessage } from "./LoginForm";

const push = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": status >= 400 ? "application/problem+json" : "application/json",
    },
  });

const problem = (status: number, code: string, extra: Record<string, unknown> = {}) =>
  json(
    { type: `https://farmerapp.dev/problems/${code}`, title: code, status, code, ...extra },
    status,
  );

const sendOk = (resendAfter = 30) =>
  json(
    {
      challenge_id: "c1",
      phone_masked: "+91******3210",
      channel: "sms",
      expires_in: 300,
      resend_after: resendAfter,
      resends_left: 3,
    },
    202,
  );

const tokens = () =>
  json({
    access_token: "acc.ess.token",
    refresh_token: "r".repeat(48),
    token_type: "Bearer",
    expires_in: 900,
    user: {
      id: "u1",
      tenant_id: "t1",
      phone: "+919876543210",
      name: "Suresh",
      role: "owner",
      store_id: null,
      cluster_id: null,
      language: "en",
      status: "active",
    },
  });

function renderForm() {
  const client = new QueryClient({ defaultOptions: { mutations: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <LoginForm />
    </QueryClientProvider>,
  );
}

async function reachOtpStep(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("Mobile number"), "9876543210");
  await user.click(screen.getByRole("button", { name: "Send OTP" }));
  await screen.findByTestId("login-otp-step");
}

const bodyOf = (call: unknown[]) => JSON.parse((call[1] as RequestInit).body as string);
const spyFetch = () => vi.spyOn(globalThis, "fetch");

describe("LoginForm (C01) against the /v1/auth contract", () => {
  let fetchSpy: ReturnType<typeof spyFetch>;
  beforeEach(() => {
    fetchSpy = spyFetch();
    push.mockReset();
    setAuthToken(null);
  });
  afterEach(() => vi.restoreAllMocks());

  it("sends the OTP to /v1/auth/otp/send and shows the masked number", async () => {
    fetchSpy.mockResolvedValueOnce(sendOk());
    const user = userEvent.setup();
    renderForm();
    await reachOtpStep(user);
    expect(fetchSpy.mock.calls[0]![0]).toBe("/api/mock/v1/auth/otp/send");
    expect(bodyOf(fetchSpy.mock.calls[0]!)).toEqual({ phone: "+919876543210" });
    expect(screen.getByText("We sent a code to +91******3210")).toBeInTheDocument();
    expect(screen.getByTestId("resends-left")).toHaveTextContent("3 resends left");
  });

  it("verifies the code, stores the session and navigates home", async () => {
    fetchSpy
      .mockResolvedValueOnce(sendOk())
      .mockResolvedValueOnce(tokens())
      .mockResolvedValueOnce(json({ ok: true }));
    const user = userEvent.setup();
    renderForm();
    await reachOtpStep(user);
    await user.type(screen.getByTestId("otp-0"), "123456");
    await waitFor(() => expect(push).toHaveBeenCalledWith("/home"));
    expect(fetchSpy.mock.calls[1]![0]).toBe("/api/mock/v1/auth/otp/verify");
    expect(bodyOf(fetchSpy.mock.calls[1]!)).toEqual({
      phone: "+919876543210",
      code: "123456",
      device_name: "console",
    });
    expect(fetchSpy.mock.calls[2]![0]).toBe("/api/session");
    expect(bodyOf(fetchSpy.mock.calls[2]!)).toEqual({ refresh_token: "r".repeat(48) });
    expect(getAuthToken()).toBe("acc.ess.token");
  });

  it("shows attempts left on a wrong code", async () => {
    fetchSpy
      .mockResolvedValueOnce(sendOk())
      .mockResolvedValueOnce(problem(401, "otp_invalid", { attempts_left: 4 }));
    const user = userEvent.setup();
    renderForm();
    await reachOtpStep(user);
    await user.type(screen.getByTestId("otp-0"), "000000");
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "Sign-in failed. Check the code and try again. 4 attempts left.",
    );
    expect(push).not.toHaveBeenCalled();
  });

  it("locks the form after otp_locked", async () => {
    fetchSpy
      .mockResolvedValueOnce(sendOk())
      .mockResolvedValueOnce(problem(423, "otp_locked", { retry_after: 900 }));
    const user = userEvent.setup();
    renderForm();
    await reachOtpStep(user);
    await user.type(screen.getByTestId("otp-0"), "000000");
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Too many wrong attempts. Try again in 15 min.",
    );
    expect(screen.getByTestId("login-otp-step")).toHaveAttribute("data-locked", "true");
    expect(screen.getByTestId("otp-0")).toBeDisabled();
    expect(screen.getByRole("button", { name: "Verify and sign in" })).toBeDisabled();
  });

  it("shows the rate-limit message when a resend is refused", async () => {
    fetchSpy
      .mockResolvedValueOnce(sendOk(0)) // server says resend is available immediately
      .mockResolvedValueOnce(problem(429, "otp_rate_limited", { retry_after: 600 }));
    const user = userEvent.setup();
    renderForm();
    await reachOtpStep(user);
    await user.click(await screen.findByRole("button", { name: "Resend code" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Too many codes requested. Try again in 10 min.",
    );
  });

  it("reports unknown numbers on the phone step", async () => {
    fetchSpy.mockResolvedValueOnce(problem(404, "user_not_found"));
    const user = userEvent.setup();
    renderForm();
    await user.type(screen.getByLabelText("Mobile number"), "9876543210");
    await user.click(screen.getByRole("button", { name: "Send OTP" }));
    expect(await screen.findByText(/This number is not registered/)).toBeInTheDocument();
    expect(screen.getByTestId("login-phone-step")).toBeInTheDocument();
  });

  it("maps problem codes to message keys", () => {
    expect(loginErrorMessage(new Error("x"))).toBeUndefined();
  });
});
