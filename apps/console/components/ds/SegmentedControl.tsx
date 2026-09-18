"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

export interface SegmentedOption<V extends string> {
  value: V;
  label: string;
  icon?: React.ReactNode;
  disabled?: boolean;
}

export interface SegmentedControlProps<V extends string> {
  options: ReadonlyArray<SegmentedOption<V>>;
  value: V;
  onChange: (value: V) => void;
  /** Accessible name for the group. */
  label: string;
  size?: "sm" | "md";
  disabled?: boolean;
  className?: string;
}

export function SegmentedControl<V extends string>({
  options,
  value,
  onChange,
  label,
  size = "md",
  disabled,
  className,
}: SegmentedControlProps<V>) {
  const refs = React.useRef<Array<HTMLButtonElement | null>>([]);
  const onKeyDown = (i: number, e: React.KeyboardEvent) => {
    const enabled = options.map((o, idx) => (o.disabled ? -1 : idx)).filter((x) => x >= 0);
    const pos = enabled.indexOf(i);
    let nextPos = pos;
    if (e.key === "ArrowRight") nextPos = (pos + 1) % enabled.length;
    else if (e.key === "ArrowLeft") nextPos = (pos - 1 + enabled.length) % enabled.length;
    else return;
    e.preventDefault();
    const idx = enabled[nextPos];
    if (idx === undefined) return;
    const opt = options[idx];
    if (!opt) return;
    onChange(opt.value);
    refs.current[idx]?.focus();
  };
  return (
    <div
      role="radiogroup"
      aria-label={label}
      className={cn(
        "inline-flex rounded-input border border-border bg-background p-0.5",
        disabled && "opacity-50",
        className,
      )}
    >
      {options.map((opt, i) => {
        const selected = opt.value === value;
        return (
          <button
            key={opt.value}
            ref={(el) => {
              refs.current[i] = el;
            }}
            type="button"
            role="radio"
            aria-checked={selected}
            tabIndex={selected ? 0 : -1}
            disabled={disabled || opt.disabled}
            onClick={() => onChange(opt.value)}
            onKeyDown={(e) => onKeyDown(i, e)}
            className={cn(
              "inline-flex items-center gap-1.5 rounded-[6px] font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:cursor-not-allowed",
              size === "md" ? "h-9 px-3 text-body" : "h-7 px-2 text-small",
              selected ? "bg-surface text-text shadow-sm" : "text-text-secondary hover:text-text",
            )}
          >
            {opt.icon}
            {opt.label}
          </button>
        );
      })}
    </div>
  );
}
