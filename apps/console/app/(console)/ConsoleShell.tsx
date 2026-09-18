"use client";

import * as React from "react";
import {
  Flag,
  Home,
  Leaf,
  Package,
  Settings,
  Store,
  Users,
  UserSquare2,
  Palette,
} from "lucide-react";
import { SideNav, type SideNavItem } from "@/components/ds/SideNav";
import { TopBar } from "@/components/ds/TopBar";
import type { DateRange } from "@/components/ds/DateRangePicker";
import { ThemeToggle } from "@/components/theme/ThemeToggle";
import { useT } from "@/lib/i18n-client";

const NAV_STORAGE_KEY = "farmerapp.console.nav.collapsed";

function isoDaysAgo(days: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

export function ConsoleShell({ children }: { children: React.ReactNode }) {
  const t = useT();
  const [collapsed, setCollapsed] = React.useState(false);
  const [search, setSearch] = React.useState("");
  const [dateRange, setDateRange] = React.useState<DateRange>({
    start: isoDaysAgo(30),
    end: isoDaysAgo(0),
  });

  React.useEffect(() => {
    try {
      setCollapsed(window.localStorage.getItem(NAV_STORAGE_KEY) === "1");
    } catch {
      /* ignore */
    }
  }, []);

  const onCollapsedChange = (next: boolean) => {
    setCollapsed(next);
    try {
      window.localStorage.setItem(NAV_STORAGE_KEY, next ? "1" : "0");
    } catch {
      /* ignore */
    }
  };

  const items: SideNavItem[] = [
    { href: "/home", label: t("nav.home"), icon: <Home /> },
    { href: "/field-team", label: t("nav.fieldTeam"), icon: <UserSquare2 /> },
    { href: "/farmers", label: t("nav.farmers"), icon: <Users /> },
    { href: "/stores", label: t("nav.stores"), icon: <Store /> },
    { href: "/products", label: t("nav.products"), icon: <Package /> },
    { href: "/agronomist", label: t("nav.agronomist"), icon: <Leaf /> },
    { href: "/flags", label: t("nav.flags"), icon: <Flag /> },
    { href: "/settings", label: t("nav.settings"), icon: <Settings /> },
    { href: "/design", label: t("nav.design"), icon: <Palette /> },
  ];

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      <SideNav
        items={items}
        collapsed={collapsed}
        onCollapsedChange={onCollapsedChange}
        header={
          <span className="flex items-center gap-2 text-heading font-semibold text-primary">
            <Leaf className="size-6 shrink-0" aria-hidden="true" />
            {collapsed ? <span className="sr-only">{t("app.name")}</span> : t("app.name")}
          </span>
        }
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <TopBar
          tenantName={t("app.tenantFallback")}
          search={search}
          onSearchChange={setSearch}
          dateRange={dateRange}
          onDateRangeChange={setDateRange}
          unreadNotifications={0}
          user={{ name: "Owner", role: "owner" }}
          actions={<ThemeToggle />}
        />
        <main id="main" className="flex-1 overflow-y-auto p-6">
          {children}
        </main>
      </div>
    </div>
  );
}
