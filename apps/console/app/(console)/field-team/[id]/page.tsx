import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { OfficerView } from "./OfficerView";

export const metadata: Metadata = { title: t("fieldTeam.profileTitle") };

/** C21 Officer profile (WC-002 / AN-002). */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <OfficerView id={decodeURIComponent(id)} />
    </Suspense>
  );
}
