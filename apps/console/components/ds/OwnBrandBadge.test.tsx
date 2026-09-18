import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { OwnBrandBadge } from "./OwnBrandBadge";

describe("OwnBrandBadge", () => {
  it("renders default and custom brand", () => {
    const { rerender } = render(<OwnBrandBadge />);
    expect(screen.getByTestId("own-brand")).toHaveTextContent("Own brand");
    rerender(<OwnBrandBadge brandName="Kisan Gold" />);
    expect(screen.getByTestId("own-brand")).toHaveTextContent("Kisan Gold");
  });
  it("compact keeps accessible name", () => {
    render(<OwnBrandBadge compact />);
    expect(screen.getByText("Own brand")).toHaveClass("sr-only");
  });
});
