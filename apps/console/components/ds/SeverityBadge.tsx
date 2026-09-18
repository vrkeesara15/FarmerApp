"use client";

import { Badge } from "@/components/ui/badge";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export type Severity = "critical" | "high" | "medium" | "low";

export interface SeverityBadgeProps {
  severity: Severity;
  className?: string;
}

const variantFor = {
  critical: "danger",
  high: "danger",
  medium: "warning",
  low: "info",
} as const;

export function SeverityBadge({ severity, className }: SeverityBadgeProps) {
  const t = useT();
  return (
    <Badge
      variant={variantFor[severity]}
      data-severity={severity}
      className={cn(severity === "critical" && "border-danger", className)}
    >
      {severity === "critical" ? <span aria-hidden="true">!</span> : null}
      {t(`severity.${severity}`)}
    </Badge>
  );
}
