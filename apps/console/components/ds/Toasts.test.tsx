import { act, render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Toasts, toast } from "./Toasts";
import { ApiError } from "@/lib/api";

describe("Toasts", () => {
  it("renders toasts from helpers", async () => {
    render(<Toasts />);
    act(() => {
      toast.success("Saved", "Store updated");
      toast.fromError(new ApiError({ title: "Invalid OTP", status: 401, detail: "Code mismatch" }));
      toast.fromError(new Error("kaboom"));
    });
    expect(await screen.findByText("Saved")).toBeInTheDocument();
    expect(await screen.findByText("Invalid OTP")).toBeInTheDocument();
    expect(await screen.findByText("Something went wrong")).toBeInTheDocument();
  });
});
