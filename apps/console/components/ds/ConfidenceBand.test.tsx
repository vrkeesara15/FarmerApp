import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ConfidenceBand } from "./ConfidenceBand";

describe("ConfidenceBand", () => {
  it("renders words per level", () => {
    const { rerender } = render(<ConfidenceBand level="high" />);
    expect(screen.getByText("High confidence")).toHaveAttribute("data-level", "high");
    rerender(<ConfidenceBand level="medium" />);
    expect(screen.getByText("Medium confidence")).toBeInTheDocument();
    rerender(<ConfidenceBand level="low" />);
    expect(screen.getByText("Low confidence").className).toContain("border-dashed");
    rerender(<ConfidenceBand level="low" provisional />);
    expect(screen.getByText("Provisional")).toBeInTheDocument();
  });
});
