import * as React from "react";
import { render, screen, waitFor, fireEvent, act } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { installAdminFetch } from "@/test/mock-admin-fetch";
import { setAuthToken, setCurrentUser } from "@/lib/api";
import { adminApi } from "@/lib/admin";
import { STEP_UP_HEADER, clearStepUpToken, getStepUpToken } from "@/lib/step-up";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "./StepUp";

function signIn(role: string) {
  setAuthToken(`mock-access-${role}-1`);
  setCurrentUser({
    id: `u-${role}`,
    tenant_id: "t1",
    phone: "+919876543210",
    name: "Test",
    role,
    store_id: null,
    cluster_id: null,
    language: "en",
    status: "active",
  });
}

function Probe({ onResult }: { onResult: (r: unknown) => void }) {
  const stepUp = useStepUp();
  return (
    <button
      type="button"
      onClick={() => {
        stepUp
          .run((h) => adminApi.forceLogout("u-field_officer", h))
          .then(onResult)
          .catch(onResult);
      }}
    >
      go
    </button>
  );
}

afterEach(() => {
  vi.restoreAllMocks();
  clearStepUpToken();
  setAuthToken(null);
});

const typeCode = (code: string) =>
  [...code].forEach((d, i) =>
    fireEvent.change(screen.getByTestId(`otp-${i}`), { target: { value: d } }),
  );

describe("useStepUp dialog (SEC-028)", () => {
  it("opens on step_up_required, sends a code, verifies and retries with the token", async () => {
    const { calls } = installAdminFetch();
    signIn("owner");
    const onResult = vi.fn();
    render(
      <StepUpProvider>
        <Probe onResult={onResult} />
      </StepUpProvider>,
    );
    fireEvent.click(screen.getByText("go"));
    await screen.findByTestId("step-up-dialog");
    await screen.findByText(/\+91\*\*\*\*\*\*3210/);
    await act(async () => typeCode("123456"));
    await waitFor(() => expect(onResult).toHaveBeenCalled());
    expect(onResult.mock.calls[0]?.[0]).toMatchObject({ revoked_sessions: 2 });
    const retries = calls.filter((c) => c.path.endsWith("/force-logout"));
    expect(retries.at(-1)?.headers.get(STEP_UP_HEADER)).toBe(getStepUpToken());
    expect(screen.queryByTestId("step-up-dialog")).toBeNull();
    expect(JSON.stringify({ ...localStorage })).not.toContain("mock-stepup");
  });

  it("shows a wrong code inline and rejects as cancelled when closed", async () => {
    installAdminFetch();
    signIn("owner");
    const onResult = vi.fn();
    render(
      <StepUpProvider>
        <Probe onResult={onResult} />
      </StepUpProvider>,
    );
    fireEvent.click(screen.getByText("go"));
    await screen.findByText(/\+91\*\*\*\*\*\*3210/);
    await act(async () => typeCode("000000"));
    expect(
      await screen.findByText(/That code is not correct\. 4 attempts left\./),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(onResult).toHaveBeenCalled());
    expect(isStepUpCancelled(onResult.mock.calls[0]?.[0])).toBe(true);
  });
});
