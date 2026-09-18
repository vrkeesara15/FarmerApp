import type { Metadata } from "next";
import { t } from "@/lib/i18n";
import { LabelClaimsView } from "./LabelClaimsView";

export const metadata: Metadata = { title: t("claims.title") };

/** C51 Label claims editor (WC-005, DX-007 guardrail). */
export default function Page() {
  return <LabelClaimsView />;
}
