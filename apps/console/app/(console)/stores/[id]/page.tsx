import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { StoreDetailView } from "./StoreDetailView";

export const metadata: Metadata = { title: t("storeDetail.title") };

/** C41 Store detail (WC-004). */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <StoreDetailView id={decodeURIComponent(id)} />
    </Suspense>
  );
}
