import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { KpiCard } from "./KpiCard";

describe("KpiCard", () => {
  it("renders title, value, target progress and trend", () => {
    render(
      <KpiCard
        title="Revenue"
        value="₹12.5 L"
        target="₹15 L"
        progress={0.83}
        trend="up"
        trendValue="+8%"
      />,
    );
    expect(screen.getByText("Revenue")).toBeInTheDocument();
    expect(screen.getByText("₹12.5 L")).toBeInTheDocument();
    expect(screen.getByRole("progressbar")).toHaveAttribute("aria-valuenow", "83");
    expect(screen.getByText("Target ₹15 L")).toBeInTheDocument();
  });
  it("loading and error states", () => {
    const { rerender } = render(<KpiCard title="x" value="1" loading />);
    expect(screen.getByTestId("kpi-card")).toHaveAttribute("aria-busy", "true");
    rerender(<KpiCard title="x" value="1" error="Failed" />);
    expect(screen.getByRole("alert")).toHaveTextContent("Failed");
  });
  it("clickable renders a button", () => {
    const onClick = vi.fn();
    render(<KpiCard title="x" value="1" onClick={onClick} />);
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalled();
  });
});
