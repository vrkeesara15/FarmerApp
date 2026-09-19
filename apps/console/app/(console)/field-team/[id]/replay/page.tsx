import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { ReplayView } from "./ReplayView";

export const metadata: Metadata = { title: t("replay.title") };

/** C22 Day replay (WC-002 / AN-003): `?date=YYYY-MM-DD` plus the AN-011 filters. */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <ReplayView id={decodeURIComponent(id)} />
    </Suspense>
  );
}
