import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { VisitScoreBadge, visitStatusFor } from "./VisitScoreBadge";

describe("VisitScoreBadge", () => {
  it("maps score to status", () => {
    expect(visitStatusFor(100)).toBe("verified");
    expect(visitStatusFor(70)).toBe("verified");
    expect(visitStatusFor(69)).toBe("partial");
    expect(visitStatusFor(40)).toBe("partial");
    expect(visitStatusFor(39)).toBe("unverified");
    expect(visitStatusFor(0)).toBe("unverified");
  });

  it("renders label and clamps", () => {
    render(<VisitScoreBadge score={120} />);
    const el = screen.getByRole("img");
    expect(el).toHaveAttribute("data-status", "verified");
    expect(el).toHaveTextContent("100");
    expect(el).toHaveTextContent("Verified");
  });

  it("unverified is outline style", () => {
    render(<VisitScoreBadge score={12} showLabel={false} />);
    const el = screen.getByRole("img");
    expect(el).toHaveAttribute("data-status", "unverified");
    expect(el.className).toContain("border-danger");
    expect(el).not.toHaveTextContent("Unverified");
  });
});
