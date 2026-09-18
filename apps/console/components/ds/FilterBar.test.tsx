import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { FilterBar } from "./FilterBar";

const options = {
  clusters: [{ value: "tg", label: "Telangana" }],
  stores: [{ value: "s1", label: "Kondapur" }],
  officers: [{ value: "o1", label: "Ramesh" }],
  crops: [{ value: "cotton", label: "Cotton" }],
};

describe("FilterBar", () => {
  it("changes a filter and clears", () => {
    const onChange = vi.fn();
    render(<FilterBar value={{ crop: "cotton" }} onChange={onChange} options={options} />);
    fireEvent.change(screen.getByLabelText("Store"), { target: { value: "s1" } });
    expect(onChange).toHaveBeenCalledWith({ crop: "cotton", store: "s1" });
    fireEvent.click(screen.getByRole("button", { name: "Clear" }));
    expect(onChange).toHaveBeenCalledWith({});
  });
  it("export and hidden filters", () => {
    const onExport = vi.fn();
    render(
      <FilterBar
        value={{}}
        onChange={() => {}}
        options={options}
        onExport={onExport}
        show={{ officer: false }}
      />,
    );
    expect(screen.queryByLabelText("Officer")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Export" }));
    expect(onExport).toHaveBeenCalled();
  });
});
