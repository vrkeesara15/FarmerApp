import type { Metadata } from "next";
import { ModelReleases } from "@/components/agronomist/ModelReleases";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("models.title") };

/** DX-012 model releases (the C62 model-release view). */
export default function Page() {
  return <ModelReleases />;
}
