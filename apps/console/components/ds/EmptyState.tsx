import * as React from "react";
import { Inbox } from "lucide-react";
import { t } from "@/lib/i18n";
import { cn } from "@/lib/utils";

export interface EmptyStateProps {
  title?: string;
  /** One-line help text. */
  help?: string;
  /** Illustration or icon (24px outlined by default). */
  illustration?: React.ReactNode;
  /** Primary action, typically an <AppButton>. */
  action?: React.ReactNode;
  className?: string;
}

export function EmptyState({ title, help, illustration, action, className }: EmptyStateProps) {
  return (
    <div
      role="status"
      data-testid="empty-state"
      className={cn(
        "flex flex-col items-center justify-center gap-3 rounded-card border border-dashed border-border bg-surface px-6 py-12 text-center",
        className,
      )}
    >
      <div className="flex size-12 items-center justify-center rounded-pill bg-background text-text-muted">
        {illustration ?? <Inbox className="size-6" aria-hidden="true" />}
      </div>
      <p className="text-heading font-semibold text-text">
        {title ?? t("emptyState.defaultTitle")}
      </p>
      <p className="max-w-md text-body text-text-secondary">
        {help ?? t("emptyState.defaultHelp")}
      </p>
      {action ? <div className="mt-2">{action}</div> : null}
    </div>
  );
}
