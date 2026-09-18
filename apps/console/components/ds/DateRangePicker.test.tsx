import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { DateRangePicker, isValidRange } from "./DateRangePicker";

describe("DateRangePicker", () => {
  it("emits changes", () => {
    const onChange = vi.fn();
    render(
      <DateRangePicker value={{ start: "2026-09-01", end: "2026-09-17" }} onChange={onChange} />,
    );
    fireEvent.change(screen.getByLabelText("Start date"), { target: { value: "2026-09-02" } });
    expect(onChange).toHaveBeenCalledWith({ start: "2026-09-02", end: "2026-09-17" });
  });
  it("flags invalid range", () => {
    expect(isValidRange({ start: "2026-09-10", end: "2026-09-01" })).toBe(false);
    render(
      <DateRangePicker value={{ start: "2026-09-10", end: "2026-09-01" }} onChange={() => {}} />,
    );
    expect(screen.getByRole("alert")).toHaveTextContent("End date must be after start date");
  });
  it("disabled", () => {
    render(<DateRangePicker value={{ start: "", end: "" }} onChange={() => {}} disabled />);
    expect(screen.getByLabelText("Start date")).toBeDisabled();
  });
});
