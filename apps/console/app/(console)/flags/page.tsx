import type { Metadata } from "next";
import { FlagInbox } from "@/components/flags/FlagInbox";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("flags.title") };

/** C70 Validation inbox (WC-010). */
export default function Page() {
  return <FlagInbox />;
}
