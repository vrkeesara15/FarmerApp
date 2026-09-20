"use client";

import * as React from "react";
import { usePathname, useRouter } from "next/navigation";
import {
  BadgeIndianRupee,
  Car,
  ClipboardCheck,
  FileDown,
  Flag,
  Megaphone,
  Sprout,
  Target,
  Home,
  Leaf,
  Package,
  ScrollText,
  Settings,
  Store,
  Users,
  UserSquare2,
  UserCog,
  Palette,
} from "lucide-react";
import { SideNav, type SideNavItem } from "@/components/ds/SideNav";
import { TopBar, type TopBarProps } from "@/components/ds/TopBar";
import type { DateRange } from "@/components/ds/DateRangePicker";
import { ThemeToggle } from "@/components/theme/ThemeToggle";
import { useT } from "@/lib/i18n-client";
import { useAnalyticsFilters } from "@/lib/hooks/use-analytics-filters";
import { isAnalyticsRoute, visibleNavItems } from "@/lib/nav";
import { SessionProvider, useSession } from "@/lib/session-context";

const ROLE_KEYS = [
  "owner",
  "director",
  "cluster_head",
  "auditor",
  "store_manager",
  "accountant",
  "field_officer",
  "agronomist",
  "tenant_admin",
  "farmer",
] as const;
type RoleKey = (typeof ROLE_KEYS)[number];
const roleKey = (role: string): RoleKey =>
  (ROLE_KEYS as readonly string[]).includes(role) ? (role as RoleKey) : "owner";

const NAV_STORAGE_KEY = "farmerapp.console.nav.collapsed";

function isoDaysAgo(days: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

export function ConsoleShell({ children }: { children: React.ReactNode }) {
  return (
    <SessionProvider>
      <Shell>{children}</Shell>
    </SessionProvider>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  const t = useT();
  const session = useSession();
  const router = useRouter();
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

  const allItems: SideNavItem[] = [
    { href: "/home", label: t("nav.home"), icon: <Home /> },
    { href: "/field-team", label: t("nav.fieldTeam"), icon: <UserSquare2 /> },
    { href: "/farmers", label: t("nav.farmers"), icon: <Users /> },
    { href: "/stores", label: t("nav.stores"), icon: <Store /> },
    { href: "/products", label: t("nav.products"), icon: <Package /> },
    { href: "/products/label-claims", label: t("nav.labelClaims"), icon: <ClipboardCheck /> },
    { href: "/products/prices", label: t("nav.prices"), icon: <BadgeIndianRupee /> },
    { href: "/agronomist", label: t("nav.agronomist"), icon: <Leaf /> },
    { href: "/flags", label: t("nav.flags"), icon: <Flag /> },
    { href: "/crop-health", label: t("nav.cropHealth"), icon: <Sprout /> },
    { href: "/campaigns", label: t("nav.campaigns"), icon: <Megaphone /> },
    { href: "/incentives", label: t("nav.incentives"), icon: <Target /> },
    { href: "/travel", label: t("nav.travel"), icon: <Car /> },
    { href: "/reports", label: t("nav.reports"), icon: <FileDown /> },
    { href: "/admin/users", label: t("nav.users"), icon: <UserCog /> },
    { href: "/settings", label: t("nav.settings"), icon: <Settings /> },
    { href: "/admin/audit", label: t("nav.audit"), icon: <ScrollText /> },
    { href: "/design", label: t("nav.design"), icon: <Palette /> },
  ];
  // Role-based nav (SPEC 2.6, lib/nav.ts ROUTE_ROLES): hide what the signed-in role cannot read.
  const items = visibleNavItems(allItems, session.user?.role);
  const topBar: SharedTopBarProps = {
    tenantName: t("app.tenantFallback"),
    search,
    onSearchChange: setSearch,
    unreadNotifications: 0,
    user: session.user
      ? { name: session.user.name, role: t(`roles.${roleKey(session.user.role)}`) }
      : { name: t("session.guest") },
    onSignOut: session.user
      ? () => {
          void session.signOut().then(() => router.push("/login"));
        }
      : undefined,
    actions: <ThemeToggle />,
  };

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
        <React.Suspense
          fallback={<TopBar {...topBar} dateRange={dateRange} onDateRangeChange={setDateRange} />}
        >
          <BoundTopBar {...topBar} localRange={dateRange} onLocalRangeChange={setDateRange} />
        </React.Suspense>
        <main id="main" className="flex-1 overflow-y-auto p-6">
          {children}
        </main>
      </div>
    </div>
  );
}

type SharedTopBarProps = Omit<TopBarProps, "dateRange" | "onDateRangeChange">;

/**
 * TopBar whose date range is the page's AN-011 `from` / `to` URL parameters on the analytics
 * dashboards (same params as `useAnalyticsFilters()`, so the FilterBar and the TopBar always
 * agree and a change is a history entry); elsewhere it keeps the shell's own range.
 */
function BoundTopBar({
  localRange,
  onLocalRangeChange,
  ...props
}: SharedTopBarProps & {
  localRange: DateRange;
  onLocalRangeChange: (range: DateRange) => void;
}) {
  const pathname = usePathname();
  const { filters, setFilters } = useAnalyticsFilters();
  const bound = isAnalyticsRoute(pathname);
  const range = bound ? { start: filters.from, end: filters.to } : localRange;
  const onChange = (next: DateRange) => {
    onLocalRangeChange(next);
    if (bound) setFilters({ from: next.start, to: next.end });
  };
  return <TopBar {...props} dateRange={range} onDateRangeChange={onChange} />;
}
