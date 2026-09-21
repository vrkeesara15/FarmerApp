"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { AUDIT_ROLES, SETTINGS_ROLES, USER_READ_ROLES } from "@/lib/admin";
import { DATA_REQUEST_ROLES } from "@/lib/data-requests";
import { useT } from "@/lib/i18n-client";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";

/** C101 / C102 / C103 sub-navigation (only the screens the role may open, SPEC 2.6). */
export function AdminSubNav() {
  const t = useT();
  const pathname = usePathname() ?? "";
  const { role } = useSession();
  const links = [
    { href: "/admin/users", label: t("nav.users"), roles: USER_READ_ROLES },
    { href: "/settings", label: t("nav.settings"), roles: SETTINGS_ROLES },
    { href: "/admin/audit", label: t("nav.audit"), roles: AUDIT_ROLES },
    {
      href: "/admin/data-requests",
      label: t("nav.dataRequests"),
      roles: DATA_REQUEST_ROLES,
    },
  ].filter((l) => !role || l.roles.includes(role));
  return (
    <nav aria-label={t("admin.subnav")} className="flex gap-1 border-b border-border">
      {links.map((l) => {
        const active = pathname === l.href || pathname.startsWith(`${l.href}/`);
        return (
          <Link
            key={l.href}
            href={l.href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "-mb-px border-b-2 px-3 py-2 text-body text-text-secondary hover:text-text",
              active ? "border-primary font-semibold text-primary" : "border-transparent",
            )}
          >
            {l.label}
          </Link>
        );
      })}
    </nav>
  );
}
