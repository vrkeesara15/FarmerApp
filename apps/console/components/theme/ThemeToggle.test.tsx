import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { ThemeToggle } from "./ThemeToggle";
import { THEME_STORAGE_KEY } from "./theme";

describe("ThemeToggle", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
  });

  it("toggles data-theme and persists to localStorage", () => {
    render(<ThemeToggle />);
    const btn = screen.getByTestId("theme-toggle");
    fireEvent.click(btn);
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("dark");
    fireEvent.click(btn);
    expect(document.documentElement.getAttribute("data-theme")).toBe("light");
  });

  it("survives a throwing localStorage", () => {
    const original = Storage.prototype.setItem;
    Storage.prototype.setItem = () => {
      throw new Error("blocked");
    };
    render(<ThemeToggle />);
    fireEvent.click(screen.getByTestId("theme-toggle"));
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
    Storage.prototype.setItem = original;
  });
});
