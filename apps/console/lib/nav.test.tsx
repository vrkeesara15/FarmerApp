import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { SideNav } from "@/components/ds/SideNav";
import { canSeeReplay, canSeeRoute, filterVisibility, visibleNavItems } from "./nav";

vi.mock("next/navigation", () => ({ usePathname: () => "/home" }));

const ITEMS = [
  "/home",
  "/field-team",
  "/farmers",
  "/stores",
  "/products",
  "/flags",
  "/settings",
].map((href) => ({ href, label: href.slice(1), icon: null }));
const visible = (role: string | undefined) => visibleNavItems(ITEMS, role).map((i) => i.href);

describe("role-based nav (SPEC 2.6)", () => {
  it("owners, directors, tenant admins and auditors see every dashboard", () => {
    for (const role of ["owner", "director", "tenant_admin", "auditor", "cluster_head"])
      expect(visible(role)).toEqual(ITEMS.map((i) => i.href));
  });

  it("store managers see home, field team, farmers and stores but never a track replay", () => {
    expect(visible("store_manager")).toEqual(ITEMS.map((i) => i.href));
    expect(canSeeReplay("store_manager")).toBe(false);
  });

  it("field officers see their own field team row and farmers, not home or stores", () => {
    expect(visible("field_officer")).toEqual([
      "/field-team",
      "/farmers",
      "/products",
      "/flags",
      "/settings",
    ]);
    expect(canSeeReplay("field_officer")).toBe(true); // own track only (the API scopes it)
  });

  it("accountants see stores only; agronomists see none of the analytics screens", () => {
    expect(visible("accountant")).toEqual(["/stores", "/products", "/flags", "/settings"]);
    expect(visible("agronomist")).toEqual(["/products", "/flags", "/settings"]);
    expect(canSeeReplay("agronomist")).toBe(false);
  });

  it("detail routes follow their list route; unknown roles see nothing restricted", () => {
    expect(canSeeRoute("/field-team/off-1/replay", "accountant")).toBe(false);
    expect(canSeeRoute("/stores/store-wgl", "accountant")).toBe(true);
    expect(canSeeRoute("/farmers/f1", "farmer")).toBe(false);
    expect(canSeeRoute("/products", "farmer")).toBe(true); // not governed here
  });

  it("hides nothing while the session is still loading", () => {
    expect(visible(undefined)).toEqual(ITEMS.map((i) => i.href));
  });

  it("filters a role cannot change are hidden", () => {
    expect(filterVisibility("owner")).toEqual({ cluster: true, store: true, officer: true });
    expect(filterVisibility("cluster_head")).toEqual({
      cluster: false,
      store: true,
      officer: true,
    });
    expect(filterVisibility("store_manager")).toEqual({
      cluster: false,
      store: false,
      officer: true,
    });
    expect(filterVisibility("field_officer")).toEqual({
      cluster: false,
      store: false,
      officer: false,
    });
  });

  it("renders only the visible entries in the SideNav", () => {
    render(
      <SideNav
        items={visibleNavItems(ITEMS, "agronomist")}
        collapsed={false}
        onCollapsedChange={() => undefined}
      />,
    );
    expect(screen.queryByRole("link", { name: "home" })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "stores" })).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "products" })).toBeInTheDocument();
  });
});
