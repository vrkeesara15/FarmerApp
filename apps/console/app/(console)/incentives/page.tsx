import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { IncentivesView } from "@/components/growth/IncentivesView";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("incentives.title") };

/** C90 Targets and incentives (WC-009). */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <IncentivesView />
    </Suspense>
  );
}
