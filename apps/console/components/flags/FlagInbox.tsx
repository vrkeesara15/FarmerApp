"use client";

/**
 * C70 Validation inbox (WC-010): FlagCards grouped by severity then rule with counts, filters
 * (status, severity, rule, subject type, assigned to me, overdue), live SLA countdowns and the
 * owner on every card; cursor pagination ("Load more").
 */
import * as React from "react";
import { useRouter } from "next/navigation";
import { AppButton } from "@/components/ds/AppButton";
import { EmptyState } from "@/components/ds/EmptyState";
import { FlagCard } from "@/components/ds/FlagCard";
import type { Severity } from "@/components/ds/SeverityBadge";
import { Badge } from "@/components/ui/badge";
import {
  CheckboxField,
  PageHeader,
  QueryError,
  RoleGate,
  SelectField,
  SessionGate,
  roleLabel,
  useNow,
} from "@/components/admin/common";
import {
  FLAG_READ_ROLES,
  FLAG_SEVERITIES,
  FLAG_STATUSES,
  SUBJECT_TYPES,
  UNRESOLVED_STATUSES,
  type Flag,
  type FlagFilters,
  type FlagSeverity,
  type FlagStatus,
  type SubjectType,
} from "@/lib/flags";
import { useUserNames } from "@/lib/hooks/admin";
import { useFlagInbox } from "@/lib/hooks/flags";
import { useT } from "@/lib/i18n-client";
import { useSession } from "@/lib/session-context";
import { FlagStatusBadge } from "./FlagStatusBadge";
import { SlaTimer } from "./SlaTimer";

/** Rules shipped in rules/*.yaml (P0); the rule filter also lists any rule seen in the counts. */
export const KNOWN_RULES = ["VA-F01", "VA-F02", "VA-F03", "VA-F06"] as const;

type StatusFilter = "unresolved" | "all" | FlagStatus;

export function FlagInbox() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C70">
      <PageHeader title={t("flags.title")} subtitle={t("flags.subtitle")} />
      <SessionGate>
        <RoleGate roles={FLAG_READ_ROLES}>
          <InboxContent />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

export function ownerLabel(
  t: ReturnType<typeof useT>,
  flag: Pick<Flag, "owner_id" | "owner_role">,
  me: string | undefined,
  names: Map<string, { name: string }>,
): string {
  const role = roleLabel(t, flag.owner_role);
  if (!flag.owner_id) return t("flags.unassigned");
  if (flag.owner_id === me) return t("flags.ownerYou", { role });
  const name = names.get(flag.owner_id)?.name;
  return name ? t("flags.ownerNamed", { name, role }) : role;
}

function groupFlags(items: Flag[]): Array<{
  severity: FlagSeverity;
  rules: Array<{ rule: string; flags: Flag[] }>;
}> {
  return FLAG_SEVERITIES.map((severity) => {
    const bySeverity = items.filter((f) => f.severity === severity);
    const rules = [...new Set(bySeverity.map((f) => f.rule_id))].sort();
    return {
      severity,
      rules: rules.map((rule) => ({ rule, flags: bySeverity.filter((f) => f.rule_id === rule) })),
    };
  }).filter((g) => g.rules.length > 0);
}

function InboxContent() {
  const t = useT();
  const router = useRouter();
  const { user } = useSession();
  const names = useUserNames();
  const now = useNow(1000);
  const [status, setStatus] = React.useState<StatusFilter>("unresolved");
  const [severity, setSeverity] = React.useState<FlagSeverity | "">("");
  const [rule, setRule] = React.useState("");
  const [subject, setSubject] = React.useState<SubjectType | "">("");
  const [mine, setMine] = React.useState(false);
  const [overdue, setOverdue] = React.useState(false);

  const filters: FlagFilters = {
    status:
      status === "unresolved" ? [...UNRESOLVED_STATUSES] : status === "all" ? undefined : [status],
    severity: severity ? [severity] : undefined,
    rule_id: rule || undefined,
    subject_type: subject || undefined,
    owner_me: mine || undefined,
    overdue: overdue || undefined,
  };
  const inbox = useFlagInbox(filters);
  const items = React.useMemo(
    () => (inbox.data?.pages ?? []).flatMap((p) => p.items),
    [inbox.data],
  );
  const counts = inbox.data?.pages[0]?.counts;
  const ruleOptions = [...new Set([...KNOWN_RULES, ...Object.keys(counts?.by_rule ?? {})])].sort();
  const groups = groupFlags(items);
  const filtered = status !== "unresolved" || severity || rule || subject || mine || overdue;

  const clear = () => {
    setStatus("unresolved");
    setSeverity("");
    setRule("");
    setSubject("");
    setMine(false);
    setOverdue(false);
  };

  return (
    <div className="flex flex-col gap-4">
      <section
        aria-label={t("flags.filters.label")}
        className="flex flex-wrap items-end gap-3 rounded-card border border-border bg-surface p-3"
        data-testid="flag-filters"
      >
        <SelectField
          label={t("flags.filters.status")}
          value={status}
          onChange={(e) => setStatus(e.target.value as StatusFilter)}
          options={[
            { value: "unresolved", label: t("flags.filters.unresolved") },
            { value: "all", label: t("common.all") },
            ...FLAG_STATUSES.map((s) => ({ value: s, label: t(`flags.status.${s}`) })),
          ]}
          className="min-w-44"
        />
        <SelectField
          label={t("flags.filters.severity")}
          value={severity}
          onChange={(e) => setSeverity(e.target.value as FlagSeverity | "")}
          emptyLabel={t("common.all")}
          options={FLAG_SEVERITIES.map((s) => ({ value: s, label: t(`severity.${s}`) }))}
          className="min-w-36"
        />
        <SelectField
          label={t("flags.filters.rule")}
          value={rule}
          onChange={(e) => setRule(e.target.value)}
          emptyLabel={t("common.all")}
          options={ruleOptions.map((r) => ({ value: r, label: r }))}
          className="min-w-36"
        />
        <SelectField
          label={t("flags.filters.subject")}
          value={subject}
          onChange={(e) => setSubject(e.target.value as SubjectType | "")}
          emptyLabel={t("common.all")}
          options={SUBJECT_TYPES.map((s) => ({ value: s, label: t(`flags.subject.${s}`) }))}
          className="min-w-36"
        />
        <div className="flex flex-col gap-2 pb-1">
          <CheckboxField
            label={t("flags.filters.mine")}
            checked={mine}
            onChange={(e) => setMine(e.target.checked)}
          />
          <CheckboxField
            label={t("flags.filters.overdue")}
            checked={overdue}
            onChange={(e) => setOverdue(e.target.checked)}
          />
        </div>
        {filtered ? (
          <AppButton variant="tertiary" size="M" onClick={clear}>
            {t("common.clear")}
          </AppButton>
        ) : null}
      </section>

      {counts ? (
        <div className="flex flex-wrap items-center gap-2" data-testid="flag-counts">
          <span className="tnum text-body font-semibold">
            {t("flags.total", { n: counts.total })}
          </span>
          {FLAG_SEVERITIES.map((s) => (
            <Badge
              key={s}
              variant={s === "high" ? "danger" : s === "medium" ? "warning" : "info"}
              data-testid={`count-${s}`}
            >
              {t(`severity.${s}`)} · <span className="tnum">{counts.by_severity[s] ?? 0}</span>
            </Badge>
          ))}
        </div>
      ) : null}

      {inbox.isLoading ? (
        <div className="grid gap-3 md:grid-cols-2">
          {Array.from({ length: 4 }, (_, i) => (
            <FlagCard
              key={i}
              loading
              id=""
              title=""
              severity="low"
              rule=""
              raisedAt={new Date(0)}
            />
          ))}
        </div>
      ) : inbox.error ? (
        <QueryError error={inbox.error} onRetry={() => void inbox.refetch()} />
      ) : items.length === 0 ? (
        <EmptyState
          title={filtered ? t("flags.emptyFilteredTitle") : t("flags.emptyTitle")}
          help={filtered ? t("flags.emptyFiltered") : t("flags.empty")}
        />
      ) : (
        <div className="flex flex-col gap-6">
          {groups.map((group) => (
            <section
              key={group.severity}
              aria-labelledby={`sev-${group.severity}`}
              data-testid={`severity-group-${group.severity}`}
              className="flex flex-col gap-3"
            >
              <h2 id={`sev-${group.severity}`} className="text-heading font-semibold">
                {t("flags.groupSeverity", {
                  severity: t(`severity.${group.severity}`),
                  n: counts?.by_severity[group.severity] ?? 0,
                })}
              </h2>
              {group.rules.map((r) => (
                <div
                  key={r.rule}
                  className="flex flex-col gap-2"
                  data-testid={`rule-group-${group.severity}-${r.rule}`}
                >
                  <h3 className="text-small font-semibold uppercase tracking-wide text-text-muted">
                    {t("flags.groupRule", { rule: r.rule, n: r.flags.length })}
                  </h3>
                  <div className="grid gap-3 md:grid-cols-2">
                    {r.flags.map((f) => (
                      <FlagCard
                        key={f.id}
                        id={f.id}
                        title={f.title}
                        severity={(f.severity as Severity) ?? "low"}
                        rule={t("flags.ruleVersion", { rule: f.rule_id, version: f.rule_version })}
                        summary={t("flags.subjectLine", {
                          subject: t(`flags.subject.${f.subject_type as SubjectType}`),
                        })}
                        raisedAt={f.created_at}
                        ownerName={ownerLabel(t, f, user?.id, names)}
                        badges={<FlagStatusBadge status={f.status} />}
                        sla={
                          <SlaTimer
                            slaDueAt={f.sla_due_at}
                            status={f.status}
                            overdue={f.overdue}
                            now={now}
                          />
                        }
                        onOpen={(id) => router.push(`/flags/${id}`)}
                      />
                    ))}
                  </div>
                </div>
              ))}
            </section>
          ))}
          {inbox.hasNextPage ? (
            <AppButton
              variant="secondary"
              onClick={() => void inbox.fetchNextPage()}
              loading={inbox.isFetchingNextPage}
              className="self-center"
            >
              {t("flags.loadMore")}
            </AppButton>
          ) : null}
        </div>
      )}
    </div>
  );
}
