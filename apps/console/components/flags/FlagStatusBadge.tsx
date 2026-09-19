"use client";

import { Badge } from "@/components/ui/badge";
import type { FlagStatus } from "@/lib/flags";
import { useT } from "@/lib/i18n-client";

const VARIANT: Record<FlagStatus, "info" | "warning" | "danger" | "success" | "neutral"> = {
  open: "info",
  in_review: "warning",
  escalated: "danger",
  resolved_valid: "success",
  resolved_fixed: "success",
  resolved_action: "success",
};

export function FlagStatusBadge({ status }: { status: FlagStatus }) {
  const t = useT();
  return (
    <Badge variant={VARIANT[status] ?? "neutral"} data-testid="flag-status" data-status={status}>
      {t(`flags.status.${status}`)}
    </Badge>
  );
}
