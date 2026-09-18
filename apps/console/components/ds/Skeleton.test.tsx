import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Skeleton, SkeletonText } from "./Skeleton";

describe("Skeleton", () => {
  it("is hidden from AT by default and announces when asked", () => {
    const { rerender } = render(<Skeleton className="h-4" />);
    expect(screen.getByTestId("skeleton")).toHaveAttribute("aria-hidden", "true");
    rerender(<Skeleton announce />);
    expect(screen.getByRole("status")).toHaveAttribute("aria-label", "Loading");
  });
  it("renders n lines", () => {
    render(<SkeletonText lines={4} />);
    expect(screen.getAllByTestId("skeleton")).toHaveLength(4);
  });
});
