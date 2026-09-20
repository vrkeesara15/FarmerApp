import type { Metadata } from "next";
import { CampaignResults } from "@/components/growth/CampaignResults";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("campaigns.results.title") };

/** C82 Campaign results (WC-008, AN-008). */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <CampaignResults id={id} />;
}
