import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { CampaignsView } from "@/components/growth/CampaignsView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("campaigns.title") };

/** C80 Campaigns list (WC-008). */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <CampaignsView />
    </Suspense>
  );
}
