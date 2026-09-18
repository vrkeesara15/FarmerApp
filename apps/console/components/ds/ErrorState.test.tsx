import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ErrorState } from "./ErrorState";

describe("ErrorState", () => {
  it("renders default and retry", () => {
    const onRetry = vi.fn();
    render(<ErrorState onRetry={onRetry} detail="500 boom" />);
    expect(screen.getByRole("alert")).toHaveTextContent("Something went wrong");
    expect(screen.getByText("500 boom")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Retry" }));
    expect(onRetry).toHaveBeenCalled();
  });
  it("retrying disables the button", () => {
    render(<ErrorState onRetry={() => {}} retrying />);
    expect(screen.getByRole("button")).toBeDisabled();
  });
});
