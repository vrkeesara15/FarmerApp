import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useState } from "react";
import { OtpInput, type OtpInputProps } from "./OtpInput";

function Harness(props: Partial<OtpInputProps>) {
  const [v, setV] = useState("");
  return <OtpInput value={v} onChange={setV} {...props} />;
}

describe("OtpInput", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("renders 6 boxes and auto-advances", () => {
    const onComplete = vi.fn();
    render(<Harness onComplete={onComplete} />);
    const boxes = [0, 1, 2, 3, 4, 5].map((i) => screen.getByTestId(`otp-${i}`) as HTMLInputElement);
    expect(boxes).toHaveLength(6);
    fireEvent.change(boxes[0]!, { target: { value: "1" } });
    expect(boxes[0]!.value).toBe("1");
    expect(document.activeElement).toBe(boxes[1]);
    fireEvent.change(boxes[1]!, { target: { value: "23456" } }); // paste
    expect(boxes[5]!.value).toBe("6");
    expect(onComplete).toHaveBeenCalledWith("123456");
  });

  it("backspace moves to previous box", () => {
    render(<Harness />);
    const b0 = screen.getByTestId("otp-0") as HTMLInputElement;
    const b1 = screen.getByTestId("otp-1") as HTMLInputElement;
    fireEvent.change(b0, { target: { value: "9" } });
    b1.focus();
    fireEvent.keyDown(b1, { key: "Backspace" });
    expect(b0.value).toBe("");
    expect(document.activeElement).toBe(b0);
  });

  it("resend timer counts down then enables resend", () => {
    const onResend = vi.fn();
    render(<Harness resendAfterSeconds={2} onResend={onResend} />);
    expect(screen.getByTestId("resend-timer")).toHaveTextContent("2s");
    act(() => {
      vi.advanceTimersByTime(2100);
    });
    const btn = screen.getByRole("button", { name: "Resend code" });
    fireEvent.click(btn);
    expect(onResend).toHaveBeenCalledOnce();
    expect(screen.getByTestId("resend-timer")).toBeInTheDocument();
  });

  it("error and disabled states", () => {
    render(<Harness error="Wrong code" disabled />);
    expect(screen.getByRole("alert")).toHaveTextContent("Wrong code");
    expect(screen.getByTestId("otp-0")).toBeDisabled();
    expect(screen.getByTestId("otp-0")).toHaveAttribute("aria-invalid", "true");
  });
});
