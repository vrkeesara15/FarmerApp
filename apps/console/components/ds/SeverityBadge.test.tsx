import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { SeverityBadge } from "./SeverityBadge";

describe("SeverityBadge", () => {
  it.each([
    ["critical", "Critical"],
    ["high", "High"],
    ["medium", "Medium"],
    ["low", "Low"],
  ] as const)("renders %s", (severity, label) => {
    render(<SeverityBadge severity={severity} />);
    expect(screen.getByText(label)).toBeInTheDocument();
    expect(screen.getByText(label).closest("[data-severity]")).toHaveAttribute(
      "data-severity",
      severity,
    );
  });
});
