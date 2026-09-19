"use client";

/** Shared pieces of the WC-010 / 011 / 012 / 103 screens: role gate, 403 state, clock, fields. */
import * as React from "react";
import { Lock } from "lucide-react";
import { ErrorState } from "@/components/ds/ErrorState";
import { ApiError } from "@/lib/api";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";

export {
  CheckboxField,
  PageHeader,
  SelectField,
  SessionGate,
  TextAreaField,
  selectClass,
} from "@/app/(console)/products/_components/fields";

/** Graceful 403: the role cannot open this screen (SPEC 2.6). */
export function ForbiddenState({ className }: { className?: string }) {
  const t = useT();
  return (
    <div
      className={cn(
        "flex flex-col items-center gap-3 rounded-card border border-border bg-surface p-8 text-center",
        className,
      )}
      data-testid="forbidden-state"
      role="status"
    >
      <Lock className="size-8 text-text-muted" aria-hidden="true" />
      <h2 className="text-heading font-semibold text-text">{t("admin.forbiddenTitle")}</h2>
      <p className="max-w-md text-body text-text-secondary">{t("admin.forbiddenHelp")}</p>
    </div>
  );
}

/** Renders children only for the listed roles (the API still enforces every call). */
export function RoleGate({
  roles,
  children,
}: {
  roles: ReadonlyArray<string>;
  children: React.ReactNode;
}) {
  const { role } = useSession();
  if (!role || !roles.includes(role)) return <ForbiddenState />;
  return <>{children}</>;
}

/** Error of a query: 403 -> ForbiddenState, anything else -> ErrorState with retry. */
export function QueryError({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const t = useT();
  if (error instanceof ApiError && error.status === 403) return <ForbiddenState />;
  return (
    <ErrorState
      title={t("errorState.defaultTitle")}
      detail={problemMessage(error, t)}
      onRetry={onRetry}
    />
  );
}

/** Current time, re-rendering every `intervalMs` (SLA countdowns). */
export function useNow(intervalMs = 1000): number {
  const [now, setNow] = React.useState(() => Date.now());
  React.useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), intervalMs);
    return () => window.clearInterval(id);
  }, [intervalMs]);
  return now;
}

const KNOWN_ROLES = [
  "owner",
  "director",
  "cluster_head",
  "auditor",
  "store_manager",
  "accountant",
  "field_officer",
  "agronomist",
  "tenant_admin",
  "farmer",
] as const;
type KnownRole = (typeof KNOWN_ROLES)[number];

/** Translated role name; unknown roles show their code. */
export function roleLabel(t: ReturnType<typeof useT>, role: string | null | undefined): string {
  if (!role) return t("common.none");
  return (KNOWN_ROLES as readonly string[]).includes(role) ? t(`roles.${role as KnownRole}`) : role;
}

/** A labelled read-only value (detail headers). */
export function Field({
  label,
  children,
  testId,
}: {
  label: string;
  children: React.ReactNode;
  testId?: string;
}) {
  return (
    <div className="flex flex-col gap-0.5" data-testid={testId}>
      <dt className="text-small text-text-muted">{label}</dt>
      <dd className="text-body text-text">{children}</dd>
    </div>
  );
}
