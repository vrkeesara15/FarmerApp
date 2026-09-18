import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { SegmentedControl } from "./SegmentedControl";

const options = [
  { value: "day", label: "Day" },
  { value: "week", label: "Week" },
  { value: "month", label: "Month", disabled: true },
] as const;

describe("SegmentedControl", () => {
  it("selects on click and arrows", () => {
    const onChange = vi.fn();
    render(<SegmentedControl options={options} value="day" onChange={onChange} label="Period" />);
    expect(screen.getByRole("radio", { name: "Day" })).toHaveAttribute("aria-checked", "true");
    fireEvent.click(screen.getByRole("radio", { name: "Week" }));
    expect(onChange).toHaveBeenCalledWith("week");
    fireEvent.keyDown(screen.getByRole("radio", { name: "Day" }), { key: "ArrowRight" });
    expect(onChange).toHaveBeenLastCalledWith("week");
    expect(screen.getByRole("radio", { name: "Month" })).toBeDisabled();
  });
});
