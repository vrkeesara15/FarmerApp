"use client";

/**
 * Error states for analytics views: 403 explains the role limit (no retry), 404 says the item
 * is outside the caller's scope, 422 filter problems offer "Reset filters", anything else is
 * the generic ErrorState with retry.
 */
import * as React from "react";
import { Lock, SearchX, SlidersHorizontal } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { EmptyState } from "@/components/ds/EmptyState";
import { ErrorState } from "@/components/ds/ErrorState";
import { ApiError } from "@/lib/api";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";

export interface ProblemStateProps {
  error: unknown;
  onRetry?: () => void;
  onResetFilters?: () => void;
  /** Overrides the 403 help (e.g. the day replay's location-privacy rule). */
  forbiddenHelp?: string;
  className?: string;
}

export function ProblemState({
  error,
  onRetry,
  onResetFilters,
  forbiddenHelp,
  className,
}: ProblemStateProps) {
  const t = useT();
  const status = error instanceof ApiError ? error.status : undefined;
  const code = error instanceof ApiError ? error.problem.code : undefined;
  if (status === 403)
    return (
      <div data-testid="forbidden-state" className={className}>
        <EmptyState
          illustration={<Lock className="size-6" aria-hidden="true" />}
          title={t("analytics.forbiddenTitle")}
          help={forbiddenHelp ?? t("analytics.forbiddenHelp")}
        />
      </div>
    );
  if (status === 404)
    return (
      <div data-testid="not-found-state" className={className}>
        <EmptyState
          illustration={<SearchX className="size-6" aria-hidden="true" />}
          title={t("analytics.notFoundTitle")}
          help={t("analytics.notFoundHelp")}
          action={
            onResetFilters ? (
              <AppButton variant="secondary" onClick={onResetFilters}>
                {t("analytics.resetFilters")}
              </AppButton>
            ) : undefined
          }
        />
      </div>
    );
  if (code === "invalid_filter_combination" || code === "invalid_date_range")
    return (
      <div data-testid="invalid-filters-state" className={className}>
        <EmptyState
          illustration={<SlidersHorizontal className="size-6" aria-hidden="true" />}
          title={t("analytics.invalidFiltersTitle")}
          help={
            code === "invalid_date_range"
              ? t("analytics.invalidRange")
              : t("analytics.invalidCombination")
          }
          action={
            onResetFilters ? (
              <AppButton variant="secondary" onClick={onResetFilters}>
                {t("analytics.resetFilters")}
              </AppButton>
            ) : undefined
          }
        />
      </div>
    );
  return (
    <ErrorState
      className={className}
      title={t("analytics.errorTitle")}
      detail={problemMessage(error, t)}
      onRetry={onRetry}
    />
  );
}

/** True for errors that should replace the whole page (no point showing sections). */
export function isBlockingProblem(error: unknown): boolean {
  return error instanceof ApiError && [403, 404, 422].includes(error.status);
}
