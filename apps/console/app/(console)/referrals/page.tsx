import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { ReferralsView } from "./ReferralsView";

export const metadata: Metadata = { title: t("referrals.title") };

/** FM-013 referrals per store. */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <ReferralsView />
    </Suspense>
  );
}
