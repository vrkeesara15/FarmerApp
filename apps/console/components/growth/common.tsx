"use client";

/** Shared pieces of the M7 growth screens (C80-C82, C90, C91, C100). */
import * as React from "react";
import Link from "next/link";
import { cn } from "@/lib/utils";
import { useT } from "@/lib/i18n-client";
import { selectClass } from "@/components/admin/common";

export { PageHeader, Section } from "@/components/analytics/Page";

/** A labelled number input bound to a number | undefined. */
export function NumberField({
  id,
  label,
  value,
  onChange,
  min,
  max,
  step,
  placeholder,
  className,
  disabled,
}: {
  id: string;
  label: string;
  value: number | undefined;
  onChange: (v: number | undefined) => void;
  min?: number;
  max?: number;
  step?: number;
  placeholder?: string;
  className?: string;
  disabled?: boolean;
}) {
  return (
    <div className={cn("flex flex-col gap-1", className)}>
      <label htmlFor={id} className="text-small font-semibold text-text-secondary">
        {label}
      </label>
      <input
        id={id}
        type="number"
        inputMode="numeric"
        value={value ?? ""}
        min={min}
        max={max}
        step={step}
        placeholder={placeholder}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value === "" ? undefined : Number(e.target.value))}
        className="tnum h-10 rounded-input border border-border bg-surface px-3 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary disabled:opacity-50"
      />
    </div>
  );
}

/** A labelled text input. */
export function TextField({
  id,
  label,
  value,
  onChange,
  placeholder,
  className,
  error,
  disabled,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  className?: string;
  error?: string;
  disabled?: boolean;
}) {
  return (
    <div className={cn("flex flex-col gap-1", className)}>
      <label htmlFor={id} className="text-small font-semibold text-text-secondary">
        {label}
      </label>
      <input
        id={id}
        type="text"
        value={value}
        placeholder={placeholder}
        disabled={disabled}
        aria-invalid={error ? true : undefined}
        onChange={(e) => onChange(e.target.value)}
        className="h-10 rounded-input border border-border bg-surface px-3 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary disabled:opacity-50"
      />
      {error ? (
        <p className="text-small text-danger" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}

/** Multi-select as a scrollable checkbox list (no native multiple: hard to use and to test). */
export function CheckboxList({
  label,
  options,
  selected,
  onChange,
  testId,
}: {
  label: string;
  options: ReadonlyArray<{ value: string; label: string }>;
  selected: ReadonlyArray<string>;
  onChange: (next: string[]) => void;
  testId?: string;
}) {
  const group = React.useId();
  return (
    <fieldset className="flex min-w-0 flex-col gap-1" data-testid={testId}>
      <legend className="text-small font-semibold text-text-secondary">{label}</legend>
      <div className="max-h-40 overflow-y-auto rounded-input border border-border bg-surface p-2">
        {options.map((o) => {
          const id = `${group}-${o.value}`;
          const checked = selected.includes(o.value);
          return (
            <label key={o.value} htmlFor={id} className="flex items-center gap-2 py-0.5 text-body">
              <input
                id={id}
                type="checkbox"
                checked={checked}
                onChange={() =>
                  onChange(checked ? selected.filter((v) => v !== o.value) : [...selected, o.value])
                }
                className="size-4 accent-[var(--color-primary)]"
              />
              <span className="truncate">{o.label}</span>
            </label>
          );
        })}
      </div>
    </fieldset>
  );
}

/** A labelled `<select>` over a list of typed options. */
export function Choice<T extends string>({
  id,
  label,
  value,
  options,
  onChange,
  includeAll,
  className,
  disabled,
}: {
  id: string;
  label: string;
  value: T | "";
  options: ReadonlyArray<{ value: T; label: string }>;
  onChange: (v: T | "") => void;
  includeAll?: boolean;
  className?: string;
  disabled?: boolean;
}) {
  const t = useT();
  return (
    <div className={cn("flex flex-col gap-1", className)}>
      <label htmlFor={id} className="text-small font-semibold text-text-secondary">
        {label}
      </label>
      <select
        id={id}
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value as T | "")}
        className={selectClass}
      >
        {includeAll ? <option value="">{t("common.all")}</option> : null}
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </div>
  );
}

/** Small "label: value" pair used in stat strips. */
export function Stat({
  label,
  value,
  help,
  tone,
  testId,
}: {
  label: string;
  value: React.ReactNode;
  help?: React.ReactNode;
  tone?: "success" | "danger";
  testId?: string;
}) {
  return (
    <div
      className="flex min-w-0 flex-col gap-0.5 rounded-card border border-border bg-surface p-3"
      data-testid={testId}
    >
      <span className="text-small text-text-muted">{label}</span>
      <span
        className={cn(
          "tnum text-heading font-semibold",
          tone === "success" && "text-success",
          tone === "danger" && "text-danger",
        )}
      >
        {value}
      </span>
      {help ? <span className="text-small text-text-muted">{help}</span> : null}
    </div>
  );
}

/**
 * A link styled as a button. `AppButton` renders an icon next to its children, so it cannot be
 * used with Radix's `asChild` (Slot takes a single child) — this is the link equivalent.
 */
export function LinkButton({
  href,
  children,
  variant = "primary",
  testId,
  className,
}: {
  href: string;
  children: React.ReactNode;
  variant?: "primary" | "secondary";
  testId?: string;
  className?: string;
}) {
  return (
    <Link
      href={href}
      data-testid={testId}
      className={cn(
        "inline-flex h-10 items-center gap-2 rounded-input px-4 text-body font-semibold focus:outline-none focus:ring-2 focus:ring-primary",
        variant === "primary"
          ? "bg-primary text-primary-on hover:bg-primary-hover"
          : "border border-border bg-surface text-text hover:bg-background",
        className,
      )}
    >
      {children}
    </Link>
  );
}

/** An informational note box (consent, privacy, SLA explanations). */
export function Note({
  children,
  icon,
  tone = "info",
  testId,
}: {
  children: React.ReactNode;
  icon?: React.ReactNode;
  tone?: "info" | "warning";
  testId?: string;
}) {
  return (
    <p
      role="note"
      data-testid={testId}
      className={cn(
        "flex items-start gap-2 rounded-card border px-3 py-2 text-small",
        tone === "warning"
          ? "border-warning bg-warning-container text-warning"
          : "border-border bg-info-container text-info",
      )}
    >
      {icon ? <span className="mt-0.5 shrink-0">{icon}</span> : null}
      <span>{children}</span>
    </p>
  );
}
