import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { FlagCard } from "./FlagCard";

const base = {
  id: "f1",
  title: "Visit outside geofence",
  severity: "high" as const,
  rule: "VV-003",
  officerName: "Ramesh Reddy",
  raisedAt: "2026-09-17T04:30:00Z",
};

describe("FlagCard", () => {
  it("renders content and SLA", () => {
    const onOpen = vi.fn();
    render(<FlagCard {...base} slaMinutesLeft={95} onOpen={onOpen} />);
    expect(screen.getByText("Visit outside geofence")).toBeInTheDocument();
    expect(screen.getByText("High")).toBeInTheDocument();
    expect(screen.getByTestId("sla")).toHaveTextContent("Due in 1h 35m");
    expect(screen.getByText("17-09-2026 10:00")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Open flag" }));
    expect(onOpen).toHaveBeenCalledWith("f1");
  });
  it("shows breached SLA", () => {
    render(<FlagCard {...base} slaMinutesLeft={-10} />);
    expect(screen.getByTestId("sla")).toHaveTextContent("SLA breached");
  });
  it("loading", () => {
    render(<FlagCard {...base} loading />);
    expect(screen.getByTestId("flag-card")).toHaveAttribute("aria-busy", "true");
  });
});
