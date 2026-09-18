import { EmptyState } from "@/components/ds/EmptyState";
import { t, type MessageKey } from "@/lib/i18n";

export function PlaceholderPage({
  screenId,
  titleKey,
  emptyKey,
}: {
  screenId: string;
  titleKey: MessageKey;
  emptyKey: MessageKey;
}) {
  return (
    <div className="flex flex-col gap-6" data-screen={screenId}>
      <h1 className="text-display">{t(titleKey)}</h1>
      <EmptyState title={t(titleKey)} help={t(emptyKey)} />
    </div>
  );
}
