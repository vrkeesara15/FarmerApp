import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { EmptyState } from "./EmptyState";
import { AppButton } from "./AppButton";

describe("EmptyState", () => {
  it("renders defaults", () => {
    render(<EmptyState />);
    expect(screen.getByRole("status")).toHaveTextContent("Nothing here yet");
  });
  it("renders custom copy and action", () => {
    render(
      <EmptyState title="No farmers" help="Add one" action={<AppButton>Add farmer</AppButton>} />,
    );
    expect(screen.getByText("No farmers")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Add farmer" })).toBeInTheDocument();
  });
});
