import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { Farmer360View } from "./Farmer360View";

export const metadata: Metadata = { title: t("farmer360.title") };

/** C31 Farmer 360 (WC-003). */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <Farmer360View id={decodeURIComponent(id)} />
    </Suspense>
  );
}
