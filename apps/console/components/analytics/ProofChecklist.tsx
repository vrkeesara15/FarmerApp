"use client";

/**
 * ProofChecklist (design/components/ProofChecklist.md), console version: one row per proof
 * component of the visit score (VV-004) with Done / Missing text next to the icon, points
 * earned of the maximum; integrity is a caption under the list when it scored 0.
 */
import * as React from "react";
import { Check, X } from "lucide-react";
import type { ProofItem } from "@/lib/analytics";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export function ProofChecklist({ items, className }: { items: ProofItem[]; className?: string }) {
  const t = useT();
  const rows = items.filter((i) => i.kind !== "integrity");
  const integrity = items.find((i) => i.kind === "integrity");
  return (
    <div className={cn("flex flex-col gap-2", className)} data-testid="proof-checklist">
      <ul className="flex flex-col divide-y divide-border rounded-card border border-border">
        {rows.map((item) => {
          const name = t(`proof.${item.kind}`);
          const state = item.satisfied ? t("proof.done") : t("proof.missing");
          return (
            <li
              key={item.kind}
              className="flex items-center gap-2 px-3 py-2 text-small"
              aria-label={`${name}: ${state}`}
              data-satisfied={item.satisfied}
            >
              {item.satisfied ? (
                <Check className="size-4 text-success" aria-hidden="true" />
              ) : (
                <X className="size-4 text-danger" aria-hidden="true" />
              )}
              <span className="flex-1 text-text">{name}</span>
              <span className={item.satisfied ? "text-success" : "text-danger"}>{state}</span>
              <span className="tnum w-14 text-right text-text-muted">
                {t("proof.points", { points: item.points, max: item.max_points })}
              </span>
            </li>
          );
        })}
      </ul>
      {integrity && !integrity.satisfied ? (
        <p className="text-small text-warning">{t("proof.integrityIssue")}</p>
      ) : null}
    </div>
  );
}
