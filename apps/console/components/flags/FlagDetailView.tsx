"use client";

/**
 * C71 Flag detail (WC-010, VA-002): header (rule id + version, severity, status, owner,
 * watchers, SLA), the evidence bundle (map, records with links, photos from signed URLs,
 * metrics), the "Automated summary — verify evidence" box (VA-004 is P1: empty state), the
 * review actions the SPEC 6.1 state machine allows with a required note, the comment thread
 * with the subject's explanations marked, and the history from flag events.
 */
import * as React from "react";
import Link from "next/link";
import { ArrowLeft, Bot, ImageOff, MessageSquareQuote } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { Dialog } from "@/components/ds/Dialog";
import { SeverityBadge, type Severity } from "@/components/ds/SeverityBadge";
import { Skeleton } from "@/components/ds/Skeleton";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import {
  Field,
  QueryError,
  RoleGate,
  SelectField,
  SessionGate,
  TextAreaField,
  roleLabel,
  useNow,
} from "@/components/admin/common";
import {
  FLAG_READ_ROLES,
  availableActions,
  evidenceGeometry,
  isResolved,
  noteRequired,
  recordHref,
  type FlagDetail,
  type FlagEvent,
  type FlagStatus,
  type SubjectType,
} from "@/lib/flags";
import { formatDateTimeIst } from "@/lib/format";
import { useUserNames } from "@/lib/hooks/admin";
import { useAssignFlag, useCommentFlag, useFlag, useTransitionFlag } from "@/lib/hooks/flags";
import type { MessageKey } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";
import { EvidenceMap } from "./EvidenceMap";
import { ownerLabel } from "./FlagInbox";
import { FlagStatusBadge } from "./FlagStatusBadge";
import { SlaTimer } from "./SlaTimer";

const ACTION_KEYS: Record<FlagStatus, MessageKey> = {
  open: "flags.status.open",
  in_review: "flagDetail.actions.in_review",
  resolved_valid: "flagDetail.actions.resolved_valid",
  resolved_fixed: "flagDetail.actions.resolved_fixed",
  escalated: "flagDetail.actions.escalated",
  resolved_action: "flagDetail.actions.resolved_action",
};
const ACTION_HELP: Partial<Record<FlagStatus, MessageKey>> = {
  in_review: "flagDetail.actionHelp.in_review",
  resolved_valid: "flagDetail.actionHelp.resolved_valid",
  resolved_fixed: "flagDetail.actionHelp.resolved_fixed",
  escalated: "flagDetail.actionHelp.escalated",
  resolved_action: "flagDetail.actionHelp.resolved_action",
};
const ASSIGN_ROLES = ["owner", "director", "auditor", "cluster_head", "tenant_admin"];
const REVIEWER_ROLES = [
  "owner",
  "director",
  "auditor",
  "cluster_head",
  "store_manager",
  "tenant_admin",
];

export function FlagDetailView({ id }: { id: string }) {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C71">
      <Link
        href="/flags"
        className="inline-flex items-center gap-1 self-start text-small font-semibold text-primary hover:underline"
      >
        <ArrowLeft className="size-4" aria-hidden="true" />
        {t("flagDetail.back")}
      </Link>
      <SessionGate>
        <RoleGate roles={FLAG_READ_ROLES}>
          <DetailContent id={id} />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

function DetailContent({ id }: { id: string }) {
  const t = useT();
  const q = useFlag(id);
  if (q.isLoading)
    return (
      <div className="flex flex-col gap-3" aria-busy="true">
        <Skeleton announce className="h-10 w-2/3" />
        <Skeleton className="h-40 w-full" />
        <Skeleton className="h-72 w-full" />
      </div>
    );
  if (q.error || !q.data)
    return (
      <QueryError
        error={q.error ?? new Error(t("problems.notFound"))}
        onRetry={() => void q.refetch()}
      />
    );
  return <Detail flag={q.data} />;
}

function Detail({ flag }: { flag: FlagDetail }) {
  const t = useT();
  const { user, role } = useSession();
  const names = useUserNames();
  const now = useNow(1000);
  const nameOf = (uid: string | null) => {
    if (!uid) return t("flagDetail.system");
    if (uid === user?.id) return t("flagDetail.you");
    return names.get(uid)?.name ?? t("flagDetail.someone");
  };
  const geometry = React.useMemo(() => evidenceGeometry(flag.evidence.map), [flag.evidence.map]);
  const actions = availableActions(flag.status, flag.allowed_transitions, role);

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
        <div className="flex flex-wrap items-center gap-2">
          <SeverityBadge severity={(flag.severity as Severity) ?? "low"} />
          <FlagStatusBadge status={flag.status} />
          <span className="text-small text-text-muted" data-testid="flag-rule">
            {t("flags.ruleVersion", { rule: flag.rule_id, version: flag.rule_version })}
          </span>
        </div>
        <h1 className="text-display">{flag.title}</h1>
        <dl className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Field label={t("flagDetail.owner")} testId="flag-owner">
            {ownerLabel(t, flag, user?.id, names)}
          </Field>
          <Field label={t("flagDetail.watchers")} testId="flag-watchers">
            {flag.watchers.length ? flag.watchers.map(nameOf).join(", ") : t("common.none")}
          </Field>
          <Field label={t("flagDetail.sla")}>
            <SlaTimer
              slaDueAt={flag.sla_due_at}
              status={flag.status}
              overdue={flag.overdue}
              now={now}
            />
            <span className="block text-small text-text-muted">
              {t("flags.sla.dueAt", { at: formatDateTimeIst(flag.sla_due_at) })}
            </span>
          </Field>
          <Field label={t("flagDetail.subject")}>
            {t(`flags.subject.${flag.subject_type as SubjectType}`)}
          </Field>
          <Field label={t("flagDetail.raised")}>
            <span className="tnum">{formatDateTimeIst(flag.created_at)}</span>
            <span className="block text-small text-text-muted">
              {t("flagDetail.mode", { mode: flag.raised_by_mode })}
            </span>
          </Field>
          <Field label={t("flagDetail.escalationLevel")}>
            <span className="tnum">{flag.escalation_level}</span>
          </Field>
          {flag.resolved_at ? (
            <Field label={t("flagDetail.resolved")}>
              <span className="tnum">{formatDateTimeIst(flag.resolved_at)}</span>
              <span className="block text-small text-text-muted">{nameOf(flag.resolved_by)}</span>
            </Field>
          ) : null}
        </dl>
        {flag.resolution_note ? (
          <p className="rounded-input bg-background p-3 text-body" data-testid="resolution-note">
            <span className="font-semibold">{t("flagDetail.resolutionNote")}: </span>
            {flag.resolution_note}
          </p>
        ) : null}
        {actions.length ? <ActionBar flag={flag} actions={actions} /> : null}
        {role && ASSIGN_ROLES.includes(role) && !isResolved(flag.status) ? (
          <AssignControl flag={flag} />
        ) : null}
      </header>

      <AutomatedSummary />

      <div className="grid gap-6 lg:grid-cols-2">
        <Section title={t("flagDetail.map.title")}>
          <EvidenceMap points={geometry.points} polygons={geometry.polygons} />
        </Section>
        <Section title={t("flagDetail.records.title")}>
          <Records flag={flag} />
        </Section>
        <Section title={t("flagDetail.photos.title")}>
          <Photos flag={flag} />
        </Section>
        <Section title={t("flagDetail.metrics.title")}>
          <Metrics metrics={flag.evidence.metrics} />
        </Section>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Section title={t("flagDetail.thread.title")}>
          <Thread flag={flag} nameOf={nameOf} />
        </Section>
        <Section title={t("flagDetail.history.title")}>
          <History events={flag.events} nameOf={nameOf} />
        </Section>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-3 rounded-card border border-border bg-surface p-4">
      <h2 className="text-heading font-semibold">{title}</h2>
      {children}
    </section>
  );
}

function AutomatedSummary() {
  const t = useT();
  return (
    <section
      aria-labelledby="ai-summary-title"
      data-testid="ai-summary"
      className="bg-info-container/40 flex flex-col gap-2 rounded-card border border-dashed border-info p-4"
    >
      <h2 id="ai-summary-title" className="flex items-center gap-2 text-heading font-semibold">
        <Bot className="size-5 text-info" aria-hidden="true" />
        {t("flagDetail.summary.title")}
      </h2>
      <p className="text-body text-text-secondary">{t("flagDetail.summary.unavailable")}</p>
    </section>
  );
}

function ActionBar({ flag, actions }: { flag: FlagDetail; actions: FlagStatus[] }) {
  const t = useT();
  const mutation = useTransitionFlag(flag.id);
  const [target, setTarget] = React.useState<FlagStatus | null>(null);
  const [note, setNote] = React.useState("");
  const [error, setError] = React.useState<string | undefined>();

  const confirm = () => {
    if (!target) return;
    if (noteRequired(target) && !note.trim()) {
      setError(t("flagDetail.noteRequired"));
      return;
    }
    mutation.mutate(
      { to: target, note: note.trim() || null },
      {
        onSuccess: () => {
          toast.success(t("flagDetail.moved", { status: t(`flags.status.${target}`) }));
          setTarget(null);
          setNote("");
        },
        onError: (err) => setError(problemMessage(err, t)),
      },
    );
  };

  return (
    <div className="flex flex-wrap gap-2" data-testid="flag-actions">
      {actions.map((a) => (
        <AppButton
          key={a}
          size="M"
          variant={a === "escalated" ? "destructive" : a === "in_review" ? "primary" : "secondary"}
          onClick={() => {
            setTarget(a);
            setError(undefined);
          }}
        >
          {t(ACTION_KEYS[a])}
        </AppButton>
      ))}
      {target ? (
        <Dialog
          open
          onOpenChange={(o) => {
            if (!o) setTarget(null);
          }}
          title={t(ACTION_KEYS[target])}
          description={ACTION_HELP[target] ? t(ACTION_HELP[target]) : undefined}
          confirmLabel={t(ACTION_KEYS[target])}
          onConfirm={confirm}
          destructive={target === "escalated"}
          loading={mutation.isPending}
          error={error}
        >
          <TextAreaField
            label={noteRequired(target) ? t("flagDetail.note") : t("flagDetail.noteOptional")}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            maxLength={2000}
            rows={4}
            required={noteRequired(target)}
          />
        </Dialog>
      ) : null}
    </div>
  );
}

function AssignControl({ flag }: { flag: FlagDetail }) {
  const t = useT();
  const names = useUserNames();
  const mutation = useAssignFlag(flag.id);
  const reviewers = [...names.values()].filter(
    (u) => u.status === "active" && REVIEWER_ROLES.includes(u.role) && u.id !== flag.owner_id,
  );
  const [userId, setUserId] = React.useState("");
  if (!reviewers.length) return null;
  return (
    <div className="flex flex-wrap items-end gap-2">
      <SelectField
        label={t("flagDetail.reassign")}
        value={userId}
        onChange={(e) => setUserId(e.target.value)}
        emptyLabel={t("flagDetail.chooseReviewer")}
        options={reviewers.map((u) => ({
          value: u.id,
          label: `${u.name} · ${roleLabel(t, u.role)}`,
        }))}
        className="min-w-64"
      />
      <AppButton
        size="M"
        variant="secondary"
        disabled={!userId}
        loading={mutation.isPending}
        onClick={() =>
          mutation.mutate(
            { userId, note: null },
            {
              onSuccess: () => {
                toast.success(t("flagDetail.reassigned"));
                setUserId("");
              },
              onError: (err) => toast.error(problemMessage(err, t)),
            },
          )
        }
      >
        {t("flagDetail.assign")}
      </AppButton>
    </div>
  );
}

function Records({ flag }: { flag: FlagDetail }) {
  const t = useT();
  if (!flag.evidence.records.length)
    return <p className="text-small text-text-muted">{t("flagDetail.records.empty")}</p>;
  return (
    <ul className="flex flex-col divide-y divide-border" data-testid="evidence-records">
      {flag.evidence.records.map((r) => {
        const href = recordHref(r.type, r.id);
        const summary = Object.entries(r.summary ?? {});
        const label =
          typeof r.summary?.name === "string" ? r.summary.name : `${r.type} ${r.id.slice(0, 8)}`;
        return (
          <li key={`${r.type}-${r.id}`} className="flex flex-col gap-1 py-2">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="neutral">{r.type}</Badge>
              {href ? (
                <Link href={href} className="font-semibold text-primary hover:underline">
                  {label}
                </Link>
              ) : (
                <span className="font-semibold">{label}</span>
              )}
              <code className="text-small text-text-muted">{r.id}</code>
            </div>
            {summary.length ? (
              <dl className="flex flex-wrap gap-x-4 gap-y-1 text-small text-text-secondary">
                {summary
                  .filter(([k]) => k !== "name")
                  .map(([k, v]) => (
                    <div key={k} className="flex gap-1">
                      <dt className="text-text-muted">{k}:</dt>
                      <dd>{typeof v === "string" ? v : JSON.stringify(v)}</dd>
                    </div>
                  ))}
              </dl>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

function Photos({ flag }: { flag: FlagDetail }) {
  const t = useT();
  const [open, setOpen] = React.useState<number | null>(null);
  const photos = flag.evidence.photos;
  if (!photos.length)
    return <p className="text-small text-text-muted">{t("flagDetail.photos.empty")}</p>;
  const current = open === null ? null : photos[open];
  return (
    <>
      <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3" data-testid="evidence-photos">
        {photos.map((p, i) => (
          <li key={p.blob_uri}>
            {p.signed_url ? (
              <button
                type="button"
                onClick={() => setOpen(i)}
                className="block w-full overflow-hidden rounded-input border border-border focus-visible:ring-2 focus-visible:ring-primary"
                aria-label={t("flagDetail.photos.open", { n: i + 1 })}
              >
                {/* eslint-disable-next-line @next/next/no-img-element -- short-lived signed URLs */}
                <img
                  src={p.signed_url}
                  alt={t("flagDetail.photos.alt", { n: i + 1 })}
                  className="aspect-[4/3] w-full object-cover"
                  loading="lazy"
                />
              </button>
            ) : (
              <div className="flex aspect-[4/3] flex-col items-center justify-center gap-1 rounded-input border border-dashed border-border text-small text-text-muted">
                <ImageOff className="size-5" aria-hidden="true" />
                {t("flagDetail.photos.unavailable")}
              </div>
            )}
          </li>
        ))}
      </ul>
      {current?.signed_url ? (
        <Dialog
          open
          onOpenChange={(o) => {
            if (!o) setOpen(null);
          }}
          title={t("flagDetail.photos.alt", { n: (open ?? 0) + 1 })}
          description={
            current.signed_url_expires_at
              ? t("flagDetail.photos.expires", {
                  at: formatDateTimeIst(current.signed_url_expires_at),
                })
              : undefined
          }
          cancelLabel={t("common.close")}
        >
          {/* eslint-disable-next-line @next/next/no-img-element -- short-lived signed URLs */}
          <img
            src={current.signed_url}
            alt={t("flagDetail.photos.alt", { n: (open ?? 0) + 1 })}
            className="max-h-[60vh] w-full rounded-input object-contain"
          />
        </Dialog>
      ) : null}
    </>
  );
}

function Metrics({ metrics }: { metrics: Record<string, unknown> }) {
  const t = useT();
  const entries = Object.entries(metrics);
  if (!entries.length)
    return <p className="text-small text-text-muted">{t("flagDetail.metrics.empty")}</p>;
  return (
    <table className="w-full text-body" data-testid="evidence-metrics">
      <thead className="sr-only">
        <tr>
          <th>{t("flagDetail.metrics.name")}</th>
          <th>{t("flagDetail.metrics.value")}</th>
        </tr>
      </thead>
      <tbody>
        {entries.map(([k, v]) => (
          <tr key={k} className="border-b border-border last:border-0">
            <th scope="row" className="py-1.5 pr-4 text-left font-regular text-text-secondary">
              {k}
            </th>
            <td className="tnum py-1.5 text-right font-semibold">
              {typeof v === "number" || typeof v === "string"
                ? String(v)
                : Array.isArray(v)
                  ? v.join(", ")
                  : JSON.stringify(v)}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Thread({ flag, nameOf }: { flag: FlagDetail; nameOf: (id: string | null) => string }) {
  const t = useT();
  const { user } = useSession();
  const mutation = useCommentFlag(flag.id);
  const [body, setBody] = React.useState("");
  const [error, setError] = React.useState<string | undefined>();
  const isSubject = flag.subject_type === "employee" && flag.subject_id === user?.id;
  const closed = isResolved(flag.status);

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!body.trim()) {
      setError(t("validation.required"));
      return;
    }
    mutation.mutate(body.trim(), {
      onSuccess: () => {
        setBody("");
        setError(undefined);
      },
      onError: (err) => setError(problemMessage(err, t)),
    });
  };

  return (
    <div className="flex flex-col gap-3">
      {flag.comments.length === 0 ? (
        <p className="text-small text-text-muted">{t("flagDetail.thread.empty")}</p>
      ) : (
        <ol className="flex flex-col gap-2" data-testid="flag-thread">
          {flag.comments.map((c) => (
            <li
              key={c.id}
              data-testid={c.is_subject_explanation ? "subject-explanation" : "review-comment"}
              className={cn(
                "flex flex-col gap-1 rounded-input p-3",
                c.is_subject_explanation
                  ? "bg-info-container/40 border border-l-4 border-info border-l-info"
                  : "border border-border bg-background",
              )}
            >
              <div className="flex flex-wrap items-center gap-2 text-small">
                {c.is_subject_explanation ? (
                  <Badge variant="info">
                    <MessageSquareQuote className="size-3.5" aria-hidden="true" />
                    {t("flagDetail.thread.explanation")}
                  </Badge>
                ) : null}
                <span className="font-semibold">{nameOf(c.author_id)}</span>
                <time className="tnum text-text-muted" dateTime={c.created_at}>
                  {formatDateTimeIst(c.created_at)}
                </time>
              </div>
              <p className="whitespace-pre-wrap text-body">{c.body}</p>
            </li>
          ))}
        </ol>
      )}
      {closed ? (
        <p className="text-small text-text-muted">{t("flagDetail.thread.closed")}</p>
      ) : (
        <form onSubmit={submit} className="flex flex-col gap-2">
          <TextAreaField
            label={
              isSubject ? t("flagDetail.thread.explainLabel") : t("flagDetail.thread.commentLabel")
            }
            value={body}
            onChange={(e) => setBody(e.target.value)}
            maxLength={2000}
            rows={3}
            error={error}
          />
          <AppButton
            type="submit"
            size="M"
            variant="secondary"
            loading={mutation.isPending}
            className="self-end"
          >
            {isSubject ? t("flagDetail.thread.explain") : t("flagDetail.thread.comment")}
          </AppButton>
        </form>
      )}
    </div>
  );
}

function eventText(
  t: ReturnType<typeof useT>,
  e: FlagEvent,
  nameOf: (id: string | null) => string,
): string {
  const status = (s: string | null) =>
    s && s in ACTION_KEYS ? t(`flags.status.${s as FlagStatus}`) : (s ?? t("common.none"));
  switch (e.kind) {
    case "created":
      return t("flagDetail.history.created", { owner: nameOf(e.to_owner_id) });
    case "transition":
      return t("flagDetail.history.transition", {
        actor: nameOf(e.actor_id),
        from: status(e.from_status),
        to: status(e.to_status),
      });
    case "assigned":
      return t("flagDetail.history.assigned", {
        actor: nameOf(e.actor_id),
        owner: nameOf(e.to_owner_id),
      });
    case "sla_escalated":
      return t("flagDetail.history.slaEscalated", { owner: nameOf(e.to_owner_id) });
    default:
      return e.kind;
  }
}

function History({
  events,
  nameOf,
}: {
  events: FlagEvent[];
  nameOf: (id: string | null) => string;
}) {
  const t = useT();
  const ordered = [...events].reverse();
  return (
    <ol className="flex flex-col gap-3" data-testid="flag-history">
      {ordered.map((e) => (
        <li key={e.id} className="flex flex-col gap-0.5 border-l-2 border-border pl-3">
          <span className="text-body">{eventText(t, e, nameOf)}</span>
          <span className="flex flex-wrap gap-2 text-small text-text-muted">
            <time className="tnum" dateTime={e.created_at}>
              {formatDateTimeIst(e.created_at)}
            </time>
            {e.label ? (
              <span>
                {t(
                  e.label === "false_positive"
                    ? "flagDetail.history.falsePositive"
                    : "flagDetail.history.truePositive",
                )}
              </span>
            ) : null}
          </span>
          {e.note ? <p className="text-small text-text-secondary">“{e.note}”</p> : null}
        </li>
      ))}
    </ol>
  );
}
