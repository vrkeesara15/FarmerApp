import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AuditDiff } from "./AuditDiff";

describe("AuditDiff (C103)", () => {
  it("shows changed fields side by side, first and marked", () => {
    render(
      <AuditDiff
        log={{
          before: { geofence_radius_m: 150, sampling: { moving_s: 120 }, legal_name: "FCC" },
          after: { geofence_radius_m: 200, sampling: { moving_s: 120 }, legal_name: "FCC" },
        }}
      />,
    );
    const rows = screen.getAllByTestId("diff-row");
    expect(rows[0]).toHaveAttribute("data-changed", "true");
    const cells = within(rows[0]!).getAllByRole("cell");
    expect(within(rows[0]!).getByRole("rowheader")).toHaveTextContent("geofence_radius_m");
    expect(cells[0]).toHaveTextContent("150");
    expect(cells[1]).toHaveTextContent("200");
    expect(rows.slice(1).every((r) => r.getAttribute("data-changed") === "false")).toBe(true);
    expect(screen.getAllByText('{"moving_s":120}')).toHaveLength(2);
  });

  it("marks created fields as not set before", () => {
    render(<AuditDiff log={{ before: null, after: { name: "Ravi" } }} />);
    const row = screen.getByTestId("diff-row");
    expect(within(row).getAllByRole("cell")[0]).toHaveTextContent("not set");
  });

  it("says when nothing changed", () => {
    render(<AuditDiff log={{ before: null, after: null }} />);
    expect(screen.getByText("No field changes recorded.")).toBeInTheDocument();
  });
});
