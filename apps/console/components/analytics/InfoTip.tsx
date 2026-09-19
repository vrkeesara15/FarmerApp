"use client";

/**
 * Small "i" button that shows a definition (SPEC 5.2 KPI definitions) on hover and focus.
 * The text is also the button's accessible description, so screen readers get it without
 * opening anything.
 */
import * as React from "react";
import { Info } from "lucide-react";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export function InfoTip({
  name,
  text,
  className,
}: {
  name: string;
  text: string;
  className?: string;
}) {
  const t = useT();
  const id = React.useId();
  const [open, setOpen] = React.useState(false);
  return (
    <span className={cn("relative inline-flex", className)}>
      <button
        type="button"
        aria-label={t("analytics.aboutKpi", { name })}
        aria-describedby={id}
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onClick={(e) => {
          e.stopPropagation();
          setOpen((o) => !o);
        }}
        onKeyDown={(e) => {
          if (e.key === "Escape") setOpen(false);
        }}
        className="rounded-pill text-text-muted hover:text-text"
        data-testid="info-tip"
      >
        <Info className="size-3.5" aria-hidden="true" />
      </button>
      <span
        id={id}
        role="tooltip"
        className={cn(
          "absolute left-1/2 top-full z-20 mt-1 w-64 -translate-x-1/2 rounded-input border border-border bg-surface p-2 text-small font-regular text-text-secondary shadow-sheet",
          open ? "block" : "sr-only",
        )}
      >
        {text}
      </span>
    </span>
  );
}
