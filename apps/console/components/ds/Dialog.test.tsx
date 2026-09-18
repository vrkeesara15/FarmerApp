import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Dialog } from "./Dialog";

describe("Dialog", () => {
  it("renders title, description and actions", () => {
    const onConfirm = vi.fn();
    const onOpenChange = vi.fn();
    render(
      <Dialog
        open
        onOpenChange={onOpenChange}
        title="Delete store?"
        description="This cannot be undone"
        onConfirm={onConfirm}
        destructive
        confirmLabel="Delete"
      />,
    );
    expect(screen.getByRole("dialog", { name: "Delete store?" })).toBeInTheDocument();
    expect(screen.getByText("This cannot be undone")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));
    expect(onConfirm).toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });
  it("loading locks actions and shows error", () => {
    render(
      <Dialog open onOpenChange={() => {}} title="T" onConfirm={() => {}} loading error="Failed" />,
    );
    expect(screen.getByRole("button", { name: "Confirm" })).toBeDisabled();
    expect(screen.getByRole("alert")).toHaveTextContent("Failed");
  });
  it("closed renders nothing", () => {
    render(<Dialog open={false} onOpenChange={() => {}} title="Hidden" />);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });
});
