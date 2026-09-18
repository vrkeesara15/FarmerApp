"use client";

import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";

export interface SkeletonProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Announce loading to assistive tech (use on the outermost skeleton of a region only). */
  announce?: boolean;
}

/** Shimmering placeholder block. Size it with width/height classes. */
export function Skeleton({ className, announce, ...props }: SkeletonProps) {
  const t = useT();
  return (
    <div
      className={cn("bg-border/70 animate-pulse rounded-input", className)}
      aria-hidden={announce ? undefined : true}
      role={announce ? "status" : undefined}
      aria-label={announce ? t("skeleton.loading") : undefined}
      data-testid="skeleton"
      {...props}
    />
  );
}

/** Convenience: n lines of text. */
export function SkeletonText({ lines = 3, className }: { lines?: number; className?: string }) {
  return (
    <div className={cn("flex flex-col gap-2", className)} aria-hidden="true">
      {Array.from({ length: lines }, (_, i) => (
        <Skeleton key={i} className={cn("h-4", i === lines - 1 ? "w-2/3" : "w-full")} />
      ))}
    </div>
  );
}
