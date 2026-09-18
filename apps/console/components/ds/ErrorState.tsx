"use client";

import { AlertTriangle } from "lucide-react";
import { AppButton } from "./AppButton";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export interface ErrorStateProps {
  title?: string;
  help?: string;
  /** Technical detail shown in small muted text (e.g. problem.detail). */
  detail?: string;
  onRetry?: () => void;
  retrying?: boolean;
  className?: string;
}

export function ErrorState({ title, help, detail, onRetry, retrying, className }: ErrorStateProps) {
  const t = useT();
  return (
    <div
      role="alert"
      data-testid="error-state"
      className={cn(
        "border-danger/40 bg-danger-container/40 flex flex-col items-center justify-center gap-3 rounded-card border px-6 py-12 text-center",
        className,
      )}
    >
      <div className="flex size-12 items-center justify-center rounded-pill bg-danger-container text-danger">
        <AlertTriangle className="size-6" aria-hidden="true" />
      </div>
      <p className="text-heading font-semibold text-text">
        {title ?? t("errorState.defaultTitle")}
      </p>
      <p className="max-w-md text-body text-text-secondary">
        {help ?? t("errorState.defaultHelp")}
      </p>
      {detail ? <p className="max-w-md break-words text-small text-text-muted">{detail}</p> : null}
      {onRetry ? (
        <AppButton variant="secondary" onClick={onRetry} loading={retrying} className="mt-2">
          {t("common.retry")}
        </AppButton>
      ) : null}
    </div>
  );
}
