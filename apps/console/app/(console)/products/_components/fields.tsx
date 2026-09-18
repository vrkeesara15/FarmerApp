"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ErrorState } from "@/components/ds/ErrorState";
import { Skeleton } from "@/components/ds/Skeleton";
import { Badge } from "@/components/ui/badge";
import type { ClaimStatus } from "@/lib/catalog";
import { useT } from "@/lib/i18n-client";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";

export const selectClass =
  "h-11 w-full rounded-input border border-border bg-surface px-3 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary disabled:opacity-50 aria-[invalid=true]:border-danger";

export interface SelectFieldProps extends Omit<React.ComponentProps<"select">, "id"> {
  label: string;
  error?: string;
  options: ReadonlyArray<{ value: string; label: string }>;
  /** Label of the empty first option; omit for no empty option. */
  emptyLabel?: string;
  testId?: string;
}

/** Labelled native select with an inline error (same anatomy as AppTextField). */
export const SelectField = React.forwardRef<HTMLSelectElement, SelectFieldProps>(
  ({ label, error, options, emptyLabel, testId, className, ...props }, ref) => {
    const id = React.useId();
    return (
      <div className={cn("flex flex-col gap-1", className)}>
        <label htmlFor={id} className="text-small font-semibold text-text-secondary">
          {label}
        </label>
        <select
          ref={ref}
          id={id}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? `${id}-error` : undefined}
          data-testid={testId}
          className={selectClass}
          {...props}
        >
          {emptyLabel !== undefined ? <option value="">{emptyLabel}</option> : null}
          {options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
        {error ? (
          <p id={`${id}-error`} role="alert" className="text-small text-danger">
            {error}
          </p>
        ) : null}
      </div>
    );
  },
);
SelectField.displayName = "SelectField";

export interface TextAreaFieldProps extends Omit<React.ComponentProps<"textarea">, "id"> {
  label: string;
  error?: string;
  optional?: boolean;
}

export const TextAreaField = React.forwardRef<HTMLTextAreaElement, TextAreaFieldProps>(
  ({ label, error, optional, className, ...props }, ref) => {
    const t = useT();
    const id = React.useId();
    return (
      <div className={cn("flex flex-col gap-1", className)}>
        <label htmlFor={id} className="text-small font-semibold text-text-secondary">
          {label}
          {optional ? (
            <span className="ml-1 font-regular text-text-muted">({t("textField.optional")})</span>
          ) : null}
        </label>
        <textarea
          ref={ref}
          id={id}
          rows={2}
          aria-invalid={error ? true : undefined}
          className="rounded-input border border-border bg-surface px-3 py-2 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary aria-[invalid=true]:border-danger"
          {...props}
        />
        {error ? (
          <p role="alert" className="text-small text-danger">
            {error}
          </p>
        ) : null}
      </div>
    );
  },
);
TextAreaField.displayName = "TextAreaField";

export function CheckboxField({
  label,
  className,
  ...props
}: Omit<React.ComponentProps<"input">, "type"> & { label: string }) {
  const id = React.useId();
  return (
    <div className={cn("flex items-center gap-2", className)}>
      <input id={id} type="checkbox" className="size-4 accent-primary" {...props} />
      <label htmlFor={id} className="text-body text-text">
        {label}
      </label>
    </div>
  );
}

const STATUS_VARIANT: Record<ClaimStatus, "warning" | "success" | "neutral"> = {
  draft: "warning",
  approved: "success",
  retired: "neutral",
};

export function ClaimStatusChip({ status }: { status: ClaimStatus }) {
  const t = useT();
  return (
    <Badge variant={STATUS_VARIANT[status]} data-testid={`claim-status-${status}`}>
      {t(`claims.status.${status}`)}
    </Badge>
  );
}

/** C50 / C51 / C52 sub-navigation. */
export function ProductsSubNav() {
  const t = useT();
  const pathname = usePathname() ?? "";
  const links = [
    { href: "/products", label: t("nav.products") },
    { href: "/products/label-claims", label: t("nav.labelClaims") },
    { href: "/products/prices", label: t("nav.prices") },
  ];
  return (
    <nav aria-label={t("products.subnav")} className="flex gap-1 border-b border-border">
      {links.map((l) => {
        const active = pathname === l.href;
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

/** Loading / signed-out gate for data screens (queries wait for the session). */
export function SessionGate({ children }: { children: React.ReactNode }) {
  const t = useT();
  const s = useSession();
  if (s.status === "loading")
    return (
      <div className="flex flex-col gap-3" data-testid="session-loading">
        <Skeleton announce className="h-10 w-full" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  if (s.status === "anonymous")
    return (
      <div className="flex flex-col items-center gap-4" data-testid="session-signed-out">
        <ErrorState title={t("session.signedOutTitle")} help={t("session.signedOutHelp")} />
        <Link
          href="/login"
          className="rounded-input bg-primary px-4 py-2 text-body font-semibold text-primary-on"
        >
          {t("session.signIn")}
        </Link>
      </div>
    );
  return <>{children}</>;
}

export function PageHeader({
  title,
  subtitle,
  actions,
}: {
  title: string;
  subtitle?: string;
  actions?: React.ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div className="flex flex-col gap-1">
        <h1 className="text-display">{title}</h1>
        {subtitle ? <p className="text-body text-text-secondary">{subtitle}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}
