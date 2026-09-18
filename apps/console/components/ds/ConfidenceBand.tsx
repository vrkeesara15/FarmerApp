"use client";

import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export type Confidence = "high" | "medium" | "low";

export interface ConfidenceBandProps {
  level: Confidence;
  /** Low confidence diagnoses are "provisional"; shows that word instead of "Low confidence". */
  provisional?: boolean;
  className?: string;
}

const styles: Record<Confidence, string> = {
  high: "border-solid border-confidence-high bg-success-container text-confidence-high",
  medium: "border-solid border-confidence-medium bg-warning-container text-confidence-medium",
  low: "border-dashed border-confidence-low bg-transparent text-confidence-low",
};

export function ConfidenceBand({ level, provisional, className }: ConfidenceBandProps) {
  const t = useT();
  const label =
    level === "low" && provisional ? t("confidence.provisional") : t(`confidence.${level}`);
  return (
    <span
      data-level={level}
      className={cn(
        "inline-flex items-center rounded-chip border px-2 py-0.5 text-small font-semibold",
        styles[level],
        className,
      )}
    >
      {label}
    </span>
  );
}
