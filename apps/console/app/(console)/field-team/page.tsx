import type { Metadata } from "next";
import { Suspense } from "react";
import { Skeleton } from "@/components/ds/Skeleton";
import { t } from "@/lib/i18n";
import { FieldTeamView } from "./FieldTeamView";

export const metadata: Metadata = { title: t("fieldTeam.title") };

/** C20 Field team (WC-002 / AN-002). */
export default function Page() {
  return (
    <Suspense fallback={<Skeleton announce className="h-96 w-full" />}>
      <FieldTeamView />
    </Suspense>
  );
}
