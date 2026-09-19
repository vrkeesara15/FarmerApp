import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { SideNav } from "@/components/ds/SideNav";
import {
  canSeeReplay,
  canSeeRoute,
  filterVisibility,
  isAnalyticsRoute,
  visibleNavItems,
} from "./nav";

vi.mock("next/navigation", () => ({ usePathname: () => "/home" }));

const ITEMS = [
  "/home",
  "/field-team",
  "/farmers",
  "/stores",
  "/products",
  "/flags",
  "/admin/users",
  "/settings",
  "/admin/audit",
].map((href) => ({ href, label: href.slice(1), icon: null }));
const visible = (role: string | undefined) => visibleNavItems(ITEMS, role).map((i) => i.href);
const ALL = ITEMS.map((i) => i.href);
const without = (...hidden: string[]) => ALL.filter((h) => !hidden.includes(h));

describe("role-based nav (SPEC 2.6)", () => {
  it("owners, directors and tenant admins see every screen; auditors and cluster heads most", () => {
    for (const role of ["owner", "director", "tenant_admin"]) expect(visible(role)).toEqual(ALL);
    expect(visible("auditor")).toEqual(without("/settings"));
    expect(visible("cluster_head")).toEqual(without("/settings", "/admin/audit"));
  });

  it("store managers see home, field team, farmers and stores but never a track replay", () => {
    expect(visible("store_manager")).toEqual(without("/admin/users", "/settings", "/admin/audit"));
    expect(canSeeReplay("store_manager")).toBe(false);
  });

  it("field officers see their own field team row, farmers and their flags, not home or stores", () => {
    expect(visible("field_officer")).toEqual(["/field-team", "/farmers", "/products", "/flags"]);
    expect(canSeeReplay("field_officer")).toBe(true); // own track only (the API scopes it)
  });

  it("accountants see stores only; agronomists see none of the analytics or admin screens", () => {
    expect(visible("accountant")).toEqual(["/stores", "/products"]);
    expect(visible("agronomist")).toEqual(["/products"]);
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

  it("binds the TopBar date range only on the analytics dashboards", () => {
    for (const p of ["/home", "/field-team/off-1/replay", "/farmers/f1", "/stores"])
      expect(isAnalyticsRoute(p)).toBe(true);
    for (const p of ["/flags", "/homework", "/admin/users", "/settings", null])
      expect(isAnalyticsRoute(p)).toBe(false);
  });
});
