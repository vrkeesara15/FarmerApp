import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Home, Flag } from "lucide-react";
import { SideNav } from "./SideNav";

vi.mock("next/navigation", () => ({ usePathname: () => "/flags/123" }));

const items = [
  { href: "/home", label: "Home", icon: <Home /> },
  { href: "/flags", label: "Flags", icon: <Flag />, badge: 4 },
];

describe("SideNav", () => {
  it("marks active item from pathname and toggles collapse", () => {
    const onCollapsedChange = vi.fn();
    render(<SideNav items={items} collapsed={false} onCollapsedChange={onCollapsedChange} />);
    expect(screen.getByRole("link", { name: /Flags/ })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("link", { name: /Home/ })).not.toHaveAttribute("aria-current");
    fireEvent.click(screen.getByTestId("side-nav-toggle"));
    expect(onCollapsedChange).toHaveBeenCalledWith(true);
  });
  it("collapsed keeps accessible labels", () => {
    render(<SideNav items={items} collapsed onCollapsedChange={() => {}} />);
    expect(screen.getByTestId("side-nav")).toHaveAttribute("data-collapsed", "true");
    expect(screen.getByRole("link", { name: /Home/ })).toHaveAttribute("title", "Home");
    expect(screen.getByTestId("side-nav-toggle")).toHaveAttribute("aria-expanded", "false");
  });
});
