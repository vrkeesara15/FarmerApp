"use client";

import * as React from "react";
import { Download, X } from "lucide-react";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";
import { AppButton } from "./AppButton";
import { DateRangePicker, type DateRange } from "./DateRangePicker";

export interface FilterOption {
  value: string;
  label: string;
}

export interface FilterValues {
  cluster?: string;
  store?: string;
  officer?: string;
  crop?: string;
  date?: DateRange;
}

export interface FilterBarProps {
  value: FilterValues;
  onChange: (next: FilterValues) => void;
  options: {
    clusters?: FilterOption[];
    stores?: FilterOption[];
    officers?: FilterOption[];
    crops?: FilterOption[];
  };
  /** Hide individual filters when a screen does not need them. */
  show?: Partial<Record<"cluster" | "store" | "officer" | "crop" | "date", boolean>>;
  onExport?: () => void;
  exporting?: boolean;
  disabled?: boolean;
  className?: string;
}

const selectClass =
  "h-10 rounded-input border border-border bg-surface px-3 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary disabled:opacity-50";

function Select({
  id,
  label,
  value,
  options,
  onChange,
  disabled,
}: {
  id: string;
  label: string;
  value?: string;
  options: FilterOption[];
  onChange: (v: string | undefined) => void;
  disabled?: boolean;
}) {
  const t = useT();
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-small font-semibold text-text-secondary">
        {label}
      </label>
      <select
        id={id}
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value || undefined)}
        disabled={disabled}
        className={selectClass}
      >
        <option value="">{t("common.all")}</option>
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </div>
  );
}

export function FilterBar({
  value,
  onChange,
  options,
  show,
  onExport,
  exporting,
  disabled,
  className,
}: FilterBarProps) {
  const t = useT();
  const id = React.useId();
  const visible = { cluster: true, store: true, officer: true, crop: true, date: true, ...show };
  const active = Object.entries(value).filter(([k, v]) =>
    k === "date" ? !!(v as DateRange | undefined)?.start : !!v,
  ).length;
  const set = <K extends keyof FilterValues>(k: K, v: FilterValues[K]) =>
    onChange({ ...value, [k]: v });

  return (
    <div
      role="group"
      aria-label={t("filterBar.label")}
      data-testid="filter-bar"
      className={cn(
        "flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3",
        className,
      )}
    >
      {visible.cluster ? (
        <Select
          id={`${id}-cluster`}
          label={t("filterBar.cluster")}
          value={value.cluster}
          options={options.clusters ?? []}
          onChange={(v) => set("cluster", v)}
          disabled={disabled}
        />
      ) : null}
      {visible.store ? (
        <Select
          id={`${id}-store`}
          label={t("filterBar.store")}
          value={value.store}
          options={options.stores ?? []}
          onChange={(v) => set("store", v)}
          disabled={disabled}
        />
      ) : null}
      {visible.officer ? (
        <Select
          id={`${id}-officer`}
          label={t("filterBar.officer")}
          value={value.officer}
          options={options.officers ?? []}
          onChange={(v) => set("officer", v)}
          disabled={disabled}
        />
      ) : null}
      {visible.crop ? (
        <Select
          id={`${id}-crop`}
          label={t("filterBar.crop")}
          value={value.crop}
          options={options.crops ?? []}
          onChange={(v) => set("crop", v)}
          disabled={disabled}
        />
      ) : null}
      {visible.date ? (
        <div className="flex flex-col gap-1">
          <span className="text-small font-semibold text-text-secondary">
            {t("filterBar.date")}
          </span>
          <DateRangePicker
            value={value.date ?? { start: "", end: "" }}
            onChange={(d) => set("date", d)}
            disabled={disabled}
          />
        </div>
      ) : null}
      <div className="ml-auto flex items-center gap-2">
        {active > 0 ? (
          <AppButton
            variant="tertiary"
            size="M"
            icon={<X />}
            onClick={() => onChange({})}
            disabled={disabled}
          >
            {t("common.clear")}
          </AppButton>
        ) : null}
        {onExport ? (
          <AppButton
            variant="secondary"
            size="M"
            icon={<Download />}
            onClick={onExport}
            loading={exporting}
            disabled={disabled}
          >
            {t("common.export")}
          </AppButton>
        ) : null}
      </div>
    </div>
  );
}
