"use client";

import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export type VisitStatus = "verified" | "partial" | "unverified";

/** Verified >= 70, partial 40-69, unverified < 40. */
export function visitStatusFor(score: number): VisitStatus {
  if (score >= 70) return "verified";
  if (score >= 40) return "partial";
  return "unverified";
}

export interface VisitScoreBadgeProps {
  score: number;
  /** Show the status word next to the score. */
  showLabel?: boolean;
  size?: "sm" | "md";
  className?: string;
}

const styles: Record<VisitStatus, string> = {
  verified: "bg-success-container text-success border-transparent",
  partial: "bg-warning-container text-warning border-transparent",
  unverified: "bg-transparent text-danger border-danger", // outline style per tokens
};

export function VisitScoreBadge({
  score,
  showLabel = true,
  size = "md",
  className,
}: VisitScoreBadgeProps) {
  const t = useT();
  const clamped = Math.max(0, Math.min(100, Math.round(score)));
  const status = visitStatusFor(clamped);
  return (
    <span
      role="img"
      aria-label={`${t("visit.score", { n: clamped })} — ${t(`visit.${status}`)}`}
      data-status={status}
      className={cn(
        "tnum inline-flex items-center gap-1.5 rounded-pill border font-semibold",
        size === "md" ? "px-2.5 py-0.5 text-small" : "px-2 py-0 text-[11px] leading-4",
        styles[status],
        className,
      )}
    >
      <span>{clamped}</span>
      {showLabel ? <span className="font-regular">{t(`visit.${status}`)}</span> : null}
    </span>
  );
}
