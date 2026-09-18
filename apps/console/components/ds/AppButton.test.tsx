import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Plus } from "lucide-react";
import { AppButton } from "./AppButton";

describe("AppButton", () => {
  it("renders variants and sizes as data attributes", () => {
    render(
      <AppButton variant="destructive" size="L">
        Delete
      </AppButton>,
    );
    const btn = screen.getByRole("button", { name: "Delete" });
    expect(btn).toHaveAttribute("data-variant", "destructive");
    expect(btn).toHaveAttribute("data-size", "L");
  });

  it("fires onClick and renders icon", () => {
    const onClick = vi.fn();
    render(
      <AppButton icon={<Plus data-testid="icon" />} onClick={onClick}>
        Add
      </AppButton>,
    );
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledOnce();
    expect(screen.getByTestId("icon")).toBeInTheDocument();
  });

  it("loading disables and shows spinner", () => {
    const onClick = vi.fn();
    render(
      <AppButton loading onClick={onClick}>
        Save
      </AppButton>,
    );
    const btn = screen.getByRole("button");
    expect(btn).toBeDisabled();
    expect(btn).toHaveAttribute("aria-busy", "true");
    expect(screen.getByTestId("spinner")).toBeInTheDocument();
    fireEvent.click(btn);
    expect(onClick).not.toHaveBeenCalled();
  });

  it("disabled state", () => {
    render(<AppButton disabled>Off</AppButton>);
    expect(screen.getByRole("button")).toBeDisabled();
  });
});
