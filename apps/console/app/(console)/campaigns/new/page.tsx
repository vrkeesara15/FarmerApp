import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { CampaignBuilder } from "@/components/growth/CampaignBuilder";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("campaigns.builder.title") };

/** C81 Campaign builder (WC-008): segment, channel, messages per language, schedule. */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <CampaignBuilder />
    </Suspense>
  );
}
