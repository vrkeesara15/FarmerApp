"use client";

import * as React from "react";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

/** ISO dates (YYYY-MM-DD), interpreted as IST calendar days by the API. */
export interface DateRange {
  start: string;
  end: string;
}

export interface DateRangePickerProps {
  value: DateRange;
  onChange: (range: DateRange) => void;
  label?: string;
  disabled?: boolean;
  min?: string;
  max?: string;
  className?: string;
}

export function isValidRange(range: DateRange): boolean {
  if (!range.start || !range.end) return true;
  return range.start <= range.end;
}

export function DateRangePicker({
  value,
  onChange,
  label,
  disabled,
  min,
  max,
  className,
}: DateRangePickerProps) {
  const t = useT();
  const id = React.useId();
  const invalid = !isValidRange(value);
  return (
    <fieldset
      className={cn("flex flex-col gap-1", className)}
      disabled={disabled}
      aria-describedby={invalid ? `${id}-err` : undefined}
      data-testid="date-range"
    >
      <legend className="sr-only">{label ?? t("dateRange.label")}</legend>
      <div
        className={cn(
          "flex items-center gap-2 rounded-input border border-border bg-surface px-2 focus-within:ring-2 focus-within:ring-primary",
          invalid && "border-danger",
          disabled && "opacity-50",
        )}
      >
        <label htmlFor={`${id}-start`} className="text-small text-text-muted">
          {t("common.from")}
        </label>
        <input
          id={`${id}-start`}
          type="date"
          value={value.start}
          min={min}
          max={value.end || max}
          onChange={(e) => onChange({ ...value, start: e.target.value })}
          aria-label={t("dateRange.start")}
          aria-invalid={invalid || undefined}
          className="tnum h-9 bg-transparent text-body text-text focus:outline-none"
        />
        <label htmlFor={`${id}-end`} className="text-small text-text-muted">
          {t("common.to")}
        </label>
        <input
          id={`${id}-end`}
          type="date"
          value={value.end}
          min={value.start || min}
          max={max}
          onChange={(e) => onChange({ ...value, end: e.target.value })}
          aria-label={t("dateRange.end")}
          aria-invalid={invalid || undefined}
          className="tnum h-9 bg-transparent text-body text-text focus:outline-none"
        />
      </div>
      {invalid ? (
        <p id={`${id}-err`} role="alert" className="text-small text-danger">
          {t("dateRange.invalid")}
        </p>
      ) : null}
    </fieldset>
  );
}
