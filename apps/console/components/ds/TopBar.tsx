"use client";

import * as React from "react";
import { Bell, Check, ChevronDown, Languages, LogOut } from "lucide-react";
import { LOCALE_OPTIONS, setLocale } from "@/lib/i18n";
import { useLocale, useT } from "@/lib/i18n-client";
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
  /** Shown as the last item of the profile menu when provided. */
  onSignOut?: () => void;
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

/**
 * Profile menu: language (five launch languages, FA-004; the console has no dedicated
 * language screen — SPEC 13.4) and sign out. Closes on Escape, outside click or selection.
 */
function ProfileMenu({ user, onSignOut }: { user: TopBarProps["user"]; onSignOut?: () => void }) {
  const t = useT();
  const locale = useLocale();
  const [open, setOpen] = React.useState(false);
  const rootRef = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    const onClick = (e: MouseEvent) => {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("mousedown", onClick);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("mousedown", onClick);
    };
  }, [open]);

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-label={t("topbar.profile")}
        aria-haspopup="menu"
        aria-expanded={open}
        data-testid="profile-menu-trigger"
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
      {open ? (
        <div
          role="menu"
          aria-label={t("topbar.profile")}
          data-testid="profile-menu"
          className="absolute right-0 top-12 z-50 w-60 rounded-card border border-border bg-surface p-2 shadow-sheet"
        >
          <div className="flex items-center gap-2 px-2 py-1 text-small font-semibold text-text-muted">
            <Languages className="size-4" aria-hidden="true" />
            {t("language.label")}
          </div>
          {LOCALE_OPTIONS.map((option) => {
            const checked = option.locale === locale;
            return (
              <button
                key={option.locale}
                type="button"
                role="menuitemradio"
                aria-checked={checked}
                lang={option.locale}
                data-testid={`locale-${option.locale}`}
                onClick={() => {
                  setLocale(option.locale);
                  setOpen(false);
                }}
                className={cn(
                  "flex w-full items-center gap-2 rounded-input px-2 py-2 text-left text-body text-text hover:bg-background",
                  checked && "bg-primary-container",
                )}
              >
                <span className="flex-1">{option.nativeName}</span>
                <span className="text-small text-text-muted" lang={locale}>
                  {t(option.nameKey)}
                </span>
                {checked ? (
                  <Check className="size-4 text-primary" aria-hidden="true" />
                ) : (
                  <span className="size-4" aria-hidden="true" />
                )}
              </button>
            );
          })}
          {onSignOut ? (
            <>
              <hr className="my-2 border-border" />
              <button
                type="button"
                role="menuitem"
                data-testid="sign-out"
                onClick={() => {
                  setOpen(false);
                  onSignOut();
                }}
                className="flex w-full items-center gap-2 rounded-input px-2 py-2 text-left text-body text-text hover:bg-background"
              >
                <LogOut className="size-4" aria-hidden="true" />
                {t("topbar.signOut")}
              </button>
            </>
          ) : null}
        </div>
      ) : null}
    </div>
  );
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
  onSignOut,
  actions,
  className,
}: TopBarProps) {
  const t = useT();
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
        <ProfileMenu user={user} onSignOut={onSignOut} />
      </div>
    </header>
  );
}
