"use client";

import * as React from "react";
import { Bell, ChevronDown } from "lucide-react";
import { t } from "@/lib/i18n";
import { cn } from "@/lib/utils";
import { DateRangePicker, type DateRange } from "./DateRangePicker";
import { SearchBar } from "./SearchBar";

export interface TopBarProps {
  tenantName: string;
  /** Optional tenant switcher content (rendered as a dropdown trigger when provided). */
  onTenantClick?: () => void;
  search: string;
  onSearchChange: (value: string) => void;
  onSearchSubmit?: (value: string) => void;
  dateRange: DateRange;
  onDateRangeChange: (range: DateRange) => void;
  unreadNotifications?: number;
  onNotificationsClick?: () => void;
  user: { name: string; role?: string; avatarUrl?: string };
  onProfileClick?: () => void;
  /** Extra actions (theme toggle etc.). */
  actions?: React.ReactNode;
  className?: string;
}

function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? "")
    .join("");
}

export function TopBar({
  tenantName,
  onTenantClick,
  search,
  onSearchChange,
  onSearchSubmit,
  dateRange,
  onDateRangeChange,
  unreadNotifications = 0,
  onNotificationsClick,
  user,
  onProfileClick,
  actions,
  className,
}: TopBarProps) {
  return (
    <header
      data-testid="top-bar"
      className={cn(
        "flex h-14 items-center gap-4 border-b border-border bg-surface px-4",
        className,
      )}
    >
      {onTenantClick ? (
        <button
          type="button"
          onClick={onTenantClick}
          className="inline-flex items-center gap-1 rounded-input px-2 text-heading font-semibold text-text hover:bg-background"
        >
          {tenantName}
          <ChevronDown className="size-4 text-text-muted" aria-hidden="true" />
        </button>
      ) : (
        <span className="px-2 text-heading font-semibold text-text" data-testid="tenant-name">
          {tenantName}
        </span>
      )}
      <SearchBar
        value={search}
        onChange={onSearchChange}
        onSubmit={onSearchSubmit}
        placeholder={t("topbar.searchPlaceholder")}
        className="max-w-xl flex-1"
      />
      <div className="hidden lg:block">
        <DateRangePicker
          value={dateRange}
          onChange={onDateRangeChange}
          label={t("topbar.dateRange")}
        />
      </div>
      <div className="ml-auto flex items-center gap-2">
        {actions}
        <button
          type="button"
          onClick={onNotificationsClick}
          aria-label={
            unreadNotifications > 0
              ? `${t("topbar.notifications")} — ${t("topbar.unreadCount", { n: unreadNotifications })}`
              : t("topbar.notifications")
          }
          className="relative inline-flex size-10 items-center justify-center rounded-input border border-border bg-surface text-text-secondary hover:bg-background hover:text-text"
        >
          <Bell className="size-5" aria-hidden="true" />
          {unreadNotifications > 0 ? (
            <span
              className="tnum absolute -right-1 -top-1 min-w-[18px] rounded-pill bg-danger px-1 text-center text-[11px] font-semibold leading-[18px] text-primary-on"
              data-testid="unread-badge"
            >
              {unreadNotifications > 99 ? "99+" : unreadNotifications}
            </span>
          ) : null}
        </button>
        <button
          type="button"
          onClick={onProfileClick}
          aria-label={t("topbar.profile")}
          className="inline-flex h-10 items-center gap-2 rounded-input border border-border bg-surface pl-1 pr-2 hover:bg-background"
        >
          {user.avatarUrl ? (
            // eslint-disable-next-line @next/next/no-img-element -- avatar from tenant storage, sized 32px
            <img src={user.avatarUrl} alt="" className="size-8 rounded-pill object-cover" />
          ) : (
            <span
              className="flex size-8 items-center justify-center rounded-pill bg-primary-container text-small font-semibold text-primary"
              aria-hidden="true"
            >
              {initials(user.name)}
            </span>
          )}
          <span className="hidden text-left md:block">
            <span className="block text-small font-semibold leading-4 text-text">{user.name}</span>
            {user.role ? (
              <span className="block text-[11px] leading-4 text-text-muted">{user.role}</span>
            ) : null}
          </span>
          <ChevronDown className="size-4 text-text-muted" aria-hidden="true" />
        </button>
      </div>
    </header>
  );
}
