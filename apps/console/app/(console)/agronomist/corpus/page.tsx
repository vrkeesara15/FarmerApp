import type { Metadata } from "next";
import { CorpusManager } from "@/components/agronomist/CorpusManager";
import { t } from "@/lib/i18n";

export const metadata: Metadata = { title: t("corpus.title") };

/** C61 Corpus manager (WC-007). */
export default function Page() {
  return <CorpusManager />;
}
