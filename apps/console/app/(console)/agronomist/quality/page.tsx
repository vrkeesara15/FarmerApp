import type { Metadata } from "next";
import { QualityView } from "@/components/agronomist/QualityView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("quality.title") };

/** C62 Diagnosis quality (basic view; AN-007 in M7 replaces it). */
export default function Page() {
  return <QualityView />;
}
