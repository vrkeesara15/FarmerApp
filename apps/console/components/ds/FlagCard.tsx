"use client";

import * as React from "react";
import { Clock } from "lucide-react";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";
import { formatDateTimeIst } from "@/lib/format";
import { AppButton } from "./AppButton";
import { SeverityBadge, type Severity } from "./SeverityBadge";
import { Skeleton } from "./Skeleton";

export interface FlagCardProps {
  id: string;
  title: string;
  severity: Severity;
  rule: string;
  officerName?: string;
  /** Short evidence summary. */
  summary?: string;
  raisedAt: Date | string;
  /** Remaining SLA in minutes; negative = breached. */
  slaMinutesLeft?: number;
  onOpen?: (id: string) => void;
  onAssign?: (id: string) => void;
  loading?: boolean;
  className?: string;
  /** Owner of the flag (WC-010: every flag has an owner); shown in the footer. */
  ownerName?: string;
  /** Custom SLA node (e.g. a live countdown); replaces `slaMinutesLeft`. */
  sla?: React.ReactNode;
  /** Extra badges next to the severity (e.g. the review status). */
  badges?: React.ReactNode;
}

function slaText(minutes: number): string {
  const h = Math.floor(Math.abs(minutes) / 60);
  const m = Math.abs(minutes) % 60;
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

export function FlagCard({
  id,
  title,
  severity,
  rule,
  officerName,
  summary,
  raisedAt,
  slaMinutesLeft,
  onOpen,
  onAssign,
  loading,
  className,
  ownerName,
  sla,
  badges,
}: FlagCardProps) {
  const t = useT();
  if (loading) {
    return (
      <div
        className={cn(
          "flex flex-col gap-3 rounded-card border border-border bg-surface p-4",
          className,
        )}
        aria-busy="true"
        data-testid="flag-card"
      >
        <Skeleton className="h-5 w-24" />
        <Skeleton className="h-5 w-2/3" />
        <Skeleton className="h-4 w-full" />
      </div>
    );
  }
  const breached = slaMinutesLeft !== undefined && slaMinutesLeft < 0;
  return (
    <article
      data-testid="flag-card"
      data-severity={severity}
      className={cn(
        "flex flex-col gap-3 rounded-card border border-l-4 border-border bg-surface p-4",
        severity === "critical" || severity === "high"
          ? "border-l-danger"
          : severity === "medium"
            ? "border-l-warning"
            : "border-l-info",
        className,
      )}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <SeverityBadge severity={severity} />
          {badges}
          <span className="text-small text-text-muted">
            {t("flagCard.rule")}: <span className="font-semibold text-text-secondary">{rule}</span>
          </span>
        </div>
        {sla !== undefined ? (
          sla
        ) : slaMinutesLeft !== undefined ? (
          <span
            className={cn(
              "tnum inline-flex items-center gap-1 text-small font-semibold",
              breached ? "text-danger" : "text-text-secondary",
            )}
            data-testid="sla"
          >
            <Clock className="size-4" aria-hidden="true" />
            {breached
              ? t("flagCard.slaBreached")
              : t("flagCard.slaDue", { n: slaText(slaMinutesLeft) })}
          </span>
        ) : null}
      </div>
      <h3 className="text-heading font-semibold text-text">{title}</h3>
      {summary ? <p className="text-body text-text-secondary">{summary}</p> : null}
      <div className="flex flex-wrap items-center justify-between gap-2 text-small text-text-muted">
        <span>
          {officerName ? (
            <>
              {t("flagCard.officer")}: <span className="text-text-secondary">{officerName}</span>{" "}
              ·{" "}
            </>
          ) : null}
          {ownerName ? (
            <>
              {t("flagCard.owner")}:{" "}
              <span className="text-text-secondary" data-testid="flag-owner">
                {ownerName}
              </span>{" "}
              ·{" "}
            </>
          ) : null}
          <time dateTime={new Date(raisedAt).toISOString()} className="tnum">
            {formatDateTimeIst(raisedAt)}
          </time>
        </span>
        <div className="flex gap-2">
          {onAssign ? (
            <AppButton variant="tertiary" size="M" onClick={() => onAssign(id)}>
              {t("flagCard.assign")}
            </AppButton>
          ) : null}
          {onOpen ? (
            <AppButton variant="secondary" size="M" onClick={() => onOpen(id)}>
              {t("flagCard.open")}
            </AppButton>
          ) : null}
        </div>
      </div>
    </article>
  );
}
