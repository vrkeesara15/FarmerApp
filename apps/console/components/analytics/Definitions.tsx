"use client";

/** A row of SPEC 5.2 KPI names with their definitions as tooltips (tables, scorecards). */
import * as React from "react";
import type { MessageKey } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { InfoTip } from "./InfoTip";

export type DefinitionKey =
  | "verifiedVisit"
  | "uniqueFarmers"
  | "confirmationRate"
  | "conversion"
  | "ownBrandShare"
  | "activeFarmer"
  | "creditOverdue"
  | "ltv"
  | "timeOnFarm";

const NAMES: Record<DefinitionKey, MessageKey> = {
  verifiedVisit: "kpiNames.verifiedVisit",
  uniqueFarmers: "kpiNames.uniqueFarmers",
  confirmationRate: "kpiNames.confirmationRate",
  conversion: "kpiNames.conversion",
  ownBrandShare: "kpiNames.ownBrandShare",
  activeFarmer: "kpiNames.activeFarmer",
  creditOverdue: "kpiNames.creditOverdue",
  ltv: "kpiNames.ltv",
  timeOnFarm: "kpiNames.timeOnFarm",
};

const DEFS: Record<DefinitionKey, MessageKey> = {
  verifiedVisit: "kpiDefinitions.verifiedVisit",
  uniqueFarmers: "kpiDefinitions.uniqueFarmers",
  confirmationRate: "kpiDefinitions.confirmationRate",
  conversion: "kpiDefinitions.conversion",
  ownBrandShare: "kpiDefinitions.ownBrandShare",
  activeFarmer: "kpiDefinitions.activeFarmer",
  creditOverdue: "kpiDefinitions.creditOverdue",
  ltv: "kpiDefinitions.ltv",
  timeOnFarm: "kpiDefinitions.timeOnFarm",
};

export function Definitions({ keys }: { keys: DefinitionKey[] }) {
  const t = useT();
  return (
    <div
      className="flex flex-wrap items-center gap-x-4 gap-y-1 text-small text-text-secondary"
      data-testid="definitions"
    >
      <span className="font-semibold">{t("analytics.definitions")}</span>
      {keys.map((k) => (
        <span key={k} className="inline-flex items-center gap-1">
          {t(NAMES[k])}
          <InfoTip name={t(NAMES[k])} text={t(DEFS[k])} />
        </span>
      ))}
    </div>
  );
}
