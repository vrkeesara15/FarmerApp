import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Tabs } from "./Tabs";

describe("Tabs", () => {
  it("switches content", () => {
    const onValueChange = vi.fn();
    render(
      <Tabs
        label="Sections"
        onValueChange={onValueChange}
        items={[
          { value: "a", label: "Overview", content: <p>Overview body</p> },
          { value: "b", label: "Visits", count: 3, content: <p>Visits body</p> },
          { value: "c", label: "Off", disabled: true },
        ]}
      />,
    );
    expect(screen.getByText("Overview body")).toBeInTheDocument();
    fireEvent.mouseDown(screen.getByRole("tab", { name: /Visits/ }));
    fireEvent.click(screen.getByRole("tab", { name: /Visits/ }));
    expect(onValueChange).toHaveBeenCalledWith("b");
    expect(screen.getByText("Visits body")).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Off" })).toBeDisabled();
  });
});
