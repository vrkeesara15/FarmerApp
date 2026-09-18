import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { SearchBar } from "./SearchBar";

describe("SearchBar", () => {
  it("types, submits on Enter and clears", () => {
    const onChange = vi.fn();
    const onSubmit = vi.fn();
    render(<SearchBar value="ram" onChange={onChange} onSubmit={onSubmit} />);
    const input = screen.getByRole("searchbox");
    fireEvent.change(input, { target: { value: "rame" } });
    expect(onChange).toHaveBeenCalledWith("rame");
    fireEvent.keyDown(input, { key: "Enter" });
    expect(onSubmit).toHaveBeenCalledWith("ram");
    fireEvent.click(screen.getByRole("button", { name: "Clear search" }));
    expect(onChange).toHaveBeenCalledWith("");
  });
  it("disabled", () => {
    render(<SearchBar value="" onChange={() => {}} disabled />);
    expect(screen.getByRole("searchbox")).toBeDisabled();
  });
});
