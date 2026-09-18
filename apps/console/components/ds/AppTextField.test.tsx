import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AppTextField } from "./AppTextField";

describe("AppTextField", () => {
  it("links label, helper and input", () => {
    render(<AppTextField label="Name" helper="Full name" />);
    const input = screen.getByLabelText("Name");
    expect(input).toHaveAccessibleDescription("Full name");
  });

  it("shows +91 prefix for phone fields", () => {
    render(<AppTextField label="Mobile" phone />);
    expect(screen.getByTestId("prefix")).toHaveTextContent("+91");
    expect(screen.getByLabelText("Mobile")).toHaveAttribute("type", "tel");
  });

  it("error state marks invalid and announces", () => {
    render(<AppTextField label="Mobile" error="Invalid" helper="hidden" />);
    const input = screen.getByLabelText("Mobile");
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByRole("alert")).toHaveTextContent("Invalid");
    expect(screen.queryByText("hidden")).not.toBeInTheDocument();
  });

  it("disabled", () => {
    render(<AppTextField label="X" disabled />);
    expect(screen.getByLabelText("X")).toBeDisabled();
  });
});
