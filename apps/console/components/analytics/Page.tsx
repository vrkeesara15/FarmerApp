"use client";

/** Page scaffolding shared by the analytics screens (C10, C20-C22, C30-C31, C40-C41). */
import * as React from "react";
import Link from "next/link";
import { ArrowLeft, Lock } from "lucide-react";
import { EmptyState } from "@/components/ds/EmptyState";
import { ErrorState } from "@/components/ds/ErrorState";
import { Skeleton } from "@/components/ds/Skeleton";
import { useT } from "@/lib/i18n-client";
import { canSeeRoute } from "@/lib/nav";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";

export function PageHeader({
  title,
  subtitle,
  actions,
  back,
}: {
  title: string;
  subtitle?: React.ReactNode;
  actions?: React.ReactNode;
  back?: { href: string; label: string };
}) {
  return (
    <div className="flex flex-col gap-2">
      {back ? (
        <Link
          href={back.href}
          className="inline-flex w-fit items-center gap-1 text-small text-text-secondary hover:text-text"
        >
          <ArrowLeft className="size-4" aria-hidden="true" />
          {back.label}
        </Link>
      ) : null}
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex min-w-0 flex-col gap-1">
          <h1 className="text-display">{title}</h1>
          {subtitle ? <div className="text-body text-text-secondary">{subtitle}</div> : null}
        </div>
        {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
      </div>
    </div>
  );
}

export function Section({
  title,
  actions,
  children,
  className,
  testId,
  info,
}: {
  title: string;
  actions?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  testId?: string;
  info?: React.ReactNode;
}) {
  const id = React.useId();
  return (
    <section
      aria-labelledby={id}
      data-testid={testId}
      className={cn(
        "flex min-w-0 flex-col gap-3 rounded-card border border-border bg-surface p-4",
        className,
      )}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 id={id} className="flex items-center gap-1 text-heading font-semibold">
          {title}
          {info}
        </h2>
        {actions}
      </div>
      {children}
    </section>
  );
}

export function SectionSkeleton({ height = "h-60" }: { height?: string }) {
  return <Skeleton className={cn("w-full", height)} />;
}

/**
 * Session gate + role gate: while the session loads show a skeleton; signed out -> sign-in
 * link; a role that cannot read the screen (lib/nav.ts) gets the explanatory no-access state
 * instead of a request that would answer 403. The page title stays visible in every state.
 */
export function AnalyticsGate({
  path,
  title,
  children,
}: {
  path: string;
  title: string;
  children: React.ReactNode;
}) {
  const t = useT();
  const s = useSession();
  if (s.status === "authenticated" && canSeeRoute(path, s.role)) return <>{children}</>;
  return (
    <>
      <PageHeader title={title} />
      {s.status === "loading" ? (
        <div className="flex flex-col gap-3" data-testid="session-loading">
          <Skeleton announce className="h-14 w-full" />
          <Skeleton className="h-64 w-full" />
        </div>
      ) : s.status === "anonymous" ? (
        <div className="flex flex-col items-center gap-4" data-testid="session-signed-out">
          <ErrorState title={t("session.signedOutTitle")} help={t("session.signedOutHelp")} />
          <Link
            href="/login"
            className="rounded-input bg-primary px-4 py-2 text-body font-semibold text-primary-on"
          >
            {t("session.signIn")}
          </Link>
        </div>
      ) : (
        <div data-testid="forbidden-state">
          <EmptyState
            illustration={<Lock className="size-6" aria-hidden="true" />}
            title={t("analytics.forbiddenTitle")}
            help={t("analytics.forbiddenHelp")}
          />
        </div>
      )}
    </>
  );
}

/** "Showing all stores / your cluster / your store / your own work" from `filters.scope`. */
export function ScopeNote({ scope }: { scope: string | undefined }) {
  const t = useT();
  if (!scope) return null;
  const key =
    scope === "cluster"
      ? "analytics.scope.cluster"
      : scope === "store"
        ? "analytics.scope.store"
        : scope === "own"
          ? "analytics.scope.own"
          : "analytics.scope.tenant";
  return (
    <span className="text-small text-text-muted" data-testid="scope-note">
      {t(key)}
    </span>
  );
}
