import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { StatTile, trendColorClass } from "./StatTile";

describe("StatTile", () => {
  it("renders value, label and trend", () => {
    render(<StatTile value="1,25,000" label="Revenue" trend="up" trendValue="+12%" />);
    expect(screen.getByText("1,25,000")).toBeInTheDocument();
    expect(screen.getByText("Revenue")).toBeInTheDocument();
    expect(screen.getByText("Up +12% vs previous period")).toBeInTheDocument();
  });
  it("loading shows skeletons", () => {
    render(<StatTile value="x" label="y" loading />);
    expect(screen.getByTestId("stat-tile")).toHaveAttribute("aria-busy", "true");
    expect(screen.getAllByTestId("skeleton").length).toBeGreaterThan(0);
  });
  it("inverted trend colours", () => {
    expect(trendColorClass("up")).toBe("text-success");
    expect(trendColorClass("up", true)).toBe("text-danger");
    expect(trendColorClass("flat")).toBe("text-text-muted");
  });
});
