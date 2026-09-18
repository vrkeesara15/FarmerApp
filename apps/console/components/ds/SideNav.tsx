"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ChevronsLeft, ChevronsRight } from "lucide-react";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export interface SideNavItem {
  href: string;
  label: string;
  icon: React.ReactNode;
  /** Count badge (e.g. open flags). */
  badge?: number;
}

export interface SideNavProps {
  items: ReadonlyArray<SideNavItem>;
  collapsed: boolean;
  onCollapsedChange: (collapsed: boolean) => void;
  /** Override active path (defaults to usePathname). */
  activePath?: string;
  /** Slot at the top (logo / tenant). */
  header?: React.ReactNode;
  /** Slot at the bottom (theme toggle, version). */
  footer?: React.ReactNode;
  className?: string;
}

export function SideNav({
  items,
  collapsed,
  onCollapsedChange,
  activePath,
  header,
  footer,
  className,
}: SideNavProps) {
  const t = useT();
  const pathname = usePathname();
  const current = activePath ?? pathname ?? "";
  return (
    <nav
      aria-label={t("nav.primary")}
      data-collapsed={collapsed}
      data-testid="side-nav"
      className={cn(
        "flex h-full shrink-0 flex-col border-r border-border bg-surface transition-[width] duration-200",
        collapsed ? "w-16" : "w-60",
        className,
      )}
    >
      {header ? (
        <div
          className={cn(
            "flex h-14 items-center border-b border-border px-3",
            collapsed && "justify-center",
          )}
        >
          {header}
        </div>
      ) : null}
      <ul className="flex flex-1 flex-col gap-1 p-2">
        {items.map((item) => {
          const active = current === item.href || current.startsWith(`${item.href}/`);
          return (
            <li key={item.href}>
              <Link
                href={item.href}
                aria-current={active ? "page" : undefined}
                title={collapsed ? item.label : undefined}
                className={cn(
                  "flex h-10 items-center gap-3 rounded-input px-2.5 text-body text-text-secondary hover:bg-background hover:text-text",
                  active &&
                    "bg-primary-container font-semibold text-primary hover:bg-primary-container",
                  collapsed && "justify-center px-0",
                )}
              >
                <span
                  className="flex size-6 shrink-0 items-center justify-center [&_svg]:size-5"
                  aria-hidden="true"
                >
                  {item.icon}
                </span>
                <span className={cn("flex-1 truncate", collapsed && "sr-only")}>{item.label}</span>
                {item.badge ? (
                  <span
                    className={cn(
                      "tnum rounded-pill bg-danger px-1.5 text-[11px] font-semibold leading-4 text-primary-on",
                      collapsed && "absolute -mt-5 ml-6",
                    )}
                  >
                    {item.badge}
                  </span>
                ) : null}
              </Link>
            </li>
          );
        })}
      </ul>
      {footer ? (
        <div
          className={cn(
            "flex items-center gap-2 border-t border-border p-2",
            collapsed && "flex-col",
          )}
        >
          {footer}
        </div>
      ) : null}
      <button
        type="button"
        onClick={() => onCollapsedChange(!collapsed)}
        aria-label={collapsed ? t("nav.expand") : t("nav.collapse")}
        aria-expanded={!collapsed}
        data-testid="side-nav-toggle"
        className="flex h-10 items-center justify-center border-t border-border text-text-muted hover:bg-background hover:text-text"
      >
        {collapsed ? (
          <ChevronsRight className="size-5" aria-hidden="true" />
        ) : (
          <ChevronsLeft className="size-5" aria-hidden="true" />
        )}
      </button>
    </nav>
  );
}
