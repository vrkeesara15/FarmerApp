"use client";

/** Shared pieces of C60-C62: sub-navigation, SLA badge, status chips, name lookups. */
import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { AlarmClock, Eye } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import type { CorpusProblem, CorpusStatus } from "@/lib/corpus";
import { localName, reviewSla } from "@/lib/diagnosis";
import { formatDateTimeIst } from "@/lib/format";
import { useCrops } from "@/lib/hooks/catalog";
import { useCorpusProblems } from "@/lib/hooks/diagnosis";
import type { MessageKey } from "@/lib/i18n";
import { useLocale, useT } from "@/lib/i18n-client";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";

export function AgronomistSubNav() {
  const t = useT();
  const pathname = usePathname() ?? "";
  const links = [
    { href: "/agronomist", label: t("agronomist.nav.queue") },
    { href: "/agronomist/corpus", label: t("agronomist.nav.corpus") },
    { href: "/agronomist/quality", label: t("agronomist.nav.quality") },
    { href: "/agronomist/models", label: t("quality.nav.models") },
  ];
  return (
    <nav aria-label={t("agronomist.subnav")} className="flex gap-1 border-b border-border">
      {links.map((l) => {
        const active = pathname === l.href;
        return (
          <Link
            key={l.href}
            href={l.href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "-mb-px border-b-2 px-3 py-2 text-body text-text-secondary hover:text-text",
              active ? "border-primary font-semibold text-primary" : "border-transparent",
            )}
          >
            {l.label}
          </Link>
        );
      })}
    </nav>
  );
}

/** Owners read C60-C62; only agronomists act (SPEC 2.6). */
export function ReadOnlyNote() {
  const t = useT();
  const { role } = useSession();
  if (role === "agronomist" || !role) return null;
  return (
    <p
      className="flex items-center gap-2 rounded-card border border-border bg-info-container px-3 py-2 text-small text-info"
      data-testid="read-only-note"
      role="note"
    >
      <Eye className="size-4" aria-hidden="true" />
      {t("agronomist.readOnly")}
    </p>
  );
}

/** Live DX-006 countdown: warning from 18 h, danger after the 24 h SLA. */
export function SlaBadge({
  createdAt,
  overdue,
  now,
}: {
  createdAt: string;
  overdue?: boolean;
  now: number;
}) {
  const t = useT();
  const s = reviewSla(createdAt, now, { overdue });
  const text =
    s.level === "breach"
      ? t("queue.sla.breach", { n: s.text })
      : s.level === "warning"
        ? t("queue.sla.warning", { n: s.text })
        : t("queue.sla.dueIn", { n: s.text });
  return (
    <span
      data-testid="review-sla"
      data-level={s.level}
      title={formatDateTimeIst(createdAt)}
      className={cn(
        "tnum inline-flex items-center gap-1 text-small font-semibold",
        s.level === "breach"
          ? "text-danger"
          : s.level === "warning"
            ? "text-warning"
            : "text-text-secondary",
      )}
    >
      <AlarmClock className="size-4" aria-hidden="true" />
      {text}
    </span>
  );
}

const CORPUS_VARIANT: Record<CorpusStatus, "warning" | "info" | "success" | "neutral"> = {
  draft: "warning",
  reviewed: "info",
  approved: "success",
  retired: "neutral",
};

export function CorpusStatusChip({ status }: { status: CorpusStatus }) {
  const t = useT();
  return (
    <Badge variant={CORPUS_VARIANT[status]} data-testid={`corpus-status-${status}`}>
      {t(`corpus.status.${status}`)}
    </Badge>
  );
}

/** crop id -> localised crop name (catalogue crops). */
export function useCropNames(): (id: string | null | undefined) => string {
  const t = useT();
  const locale = useLocale();
  const crops = useCrops();
  const map = React.useMemo(
    () => new Map((crops.data ?? []).map((c) => [c.id, localName(c.names, locale, c.name)])),
    [crops.data, locale],
  );
  return React.useCallback(
    (id) => (id ? (map.get(id) ?? t("queue.unknownCrop")) : t("queue.unknownCrop")),
    [map, t],
  );
}

/** Every corpus problem (all statuses) by id, for candidate and label names. */
export function useProblemIndex(enabled = true) {
  const q = useCorpusProblems({}, enabled);
  const map = React.useMemo(
    () => new Map<string, CorpusProblem>((q.data?.items ?? []).map((p) => [p.id, p])),
    [q.data],
  );
  return { map, problems: q.data?.items ?? [], version: q.data?.corpus_version, query: q };
}

/** Translate a key when it exists in a known set, else show the raw value. */
export function knownLabel<K extends string>(
  t: ReturnType<typeof useT>,
  value: string | null | undefined,
  known: ReadonlyArray<K>,
  key: (v: K) => MessageKey,
): string {
  if (!value) return t("common.none");
  return (known as readonly string[]).includes(value) ? t(key(value as K)) : value;
}
