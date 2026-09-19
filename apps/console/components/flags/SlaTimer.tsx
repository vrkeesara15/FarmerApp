"use client";

import { Clock } from "lucide-react";
import { useT } from "@/lib/i18n-client";
import { formatDateTimeIst } from "@/lib/format";
import { isResolved, slaState, type FlagStatus } from "@/lib/flags";
import { cn } from "@/lib/utils";

/** Live SLA countdown (C70 / C71): overdue in the danger colour, due soon in warning. */
export function SlaTimer({
  slaDueAt,
  status,
  overdue,
  now,
  className,
}: {
  slaDueAt: string;
  status: FlagStatus;
  overdue?: boolean;
  now: number;
  className?: string;
}) {
  const t = useT();
  if (isResolved(status))
    return (
      <span className={cn("text-small text-text-muted", className)} data-testid="sla">
        {t("flags.sla.resolved")}
      </span>
    );
  const s = slaState(slaDueAt, now, { status, overdue });
  return (
    <span
      data-testid="sla"
      data-overdue={s.overdue ? "true" : "false"}
      title={t("flags.sla.dueAt", { at: formatDateTimeIst(slaDueAt) })}
      className={cn(
        "tnum inline-flex items-center gap-1 text-small font-semibold",
        s.overdue ? "text-danger" : s.dueSoon ? "text-warning" : "text-text-secondary",
        className,
      )}
    >
      <Clock className="size-4" aria-hidden="true" />
      {s.overdue ? t("flags.sla.overdue", { n: s.text }) : t("flags.sla.dueIn", { n: s.text })}
    </span>
  );
}
