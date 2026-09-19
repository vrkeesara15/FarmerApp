"use client";

/**
 * C22 Day replay (WC-002 acceptance "replay shows track, visits and gaps"; AN-003): map with
 * the track, stops, visit pins coloured by status and gaps dashed with their reason; right
 * panel timeline with visit details + ProofChecklist; a playback slider moving a marker along
 * the track and highlighting the current timeline item (lib/replay.ts).
 * Location tracks are never shown to store managers (SPEC 2.6): the page does not call the
 * API for them and explains why; a 403 from the API gets the same explanation.
 */
import * as React from "react";
import Link from "next/link";
import { Pause, Play } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { EmptyState } from "@/components/ds/EmptyState";
import { StatTile } from "@/components/ds/StatTile";
import { VisitScoreBadge } from "@/components/ds/VisitScoreBadge";
import { VISIT_COLOR } from "@/components/analytics/charts";
import { ReplayMap } from "@/components/analytics/maps";
import { AnalyticsGate, PageHeader, Section, SectionSkeleton } from "@/components/analytics/Page";
import { ProblemState } from "@/components/analytics/ProblemState";
import { ProofChecklist } from "@/components/analytics/ProofChecklist";
import { Badge } from "@/components/ui/badge";
import { ApiError } from "@/lib/api";
import type { DayReplayOut, ReplayVisit, TimelineEvent } from "@/lib/analytics";
import { isIsoDate } from "@/lib/analytics-filters";
import {
  formatDay,
  formatDecimal,
  formatSeconds,
  formatTimeIst,
  purposeKey,
  visitStatusKey,
} from "@/lib/analytics-format";
import { csvFilename, downloadCsv, type CsvColumn } from "@/lib/csv";
import { useDayReplay } from "@/lib/hooks/analytics";
import { useAnalyticsFilters, useSearchParam } from "@/lib/hooks/use-analytics-filters";
import type { TFunction } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { canSeeReplay } from "@/lib/nav";
import {
  SLIDER_MAX,
  activeTimelineIndex,
  buildPlayback,
  positionAt,
  sliderToTime,
  timeToSlider,
} from "@/lib/replay";
import { useSession } from "@/lib/session-context";
import { cn } from "@/lib/utils";

export function ReplayView({ id }: { id: string }) {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C22">
      <AnalyticsGate path="/field-team" title={t("replay.title")}>
        <ReplayGate id={id} />
      </AnalyticsGate>
    </div>
  );
}

function ReplayGate({ id }: { id: string }) {
  const t = useT();
  const { role } = useSession();
  const filters = useAnalyticsFilters();
  if (!canSeeReplay(role))
    return (
      <>
        <PageHeader
          title={t("replay.title")}
          back={{ href: `/field-team/${id}${filters.linkQuery}`, label: t("replay.backToOfficer") }}
        />
        <div data-testid="replay-forbidden">
          <ProblemState error={ROLE_FORBIDDEN} forbiddenHelp={t("replay.forbiddenHelp")} />
        </div>
      </>
    );
  return <Replay id={id} />;
}

/** Store managers are refused before any request (same state as the API's 403). */
const ROLE_FORBIDDEN = new ApiError({ title: "forbidden", status: 403, code: "forbidden" });

const STEP = 4; // slider units per tick (250 ticks for the day)
const TICK_MS = 80;

function Replay({ id }: { id: string }) {
  const t = useT();
  const filters = useAnalyticsFilters();
  const [dateParam, setDate] = useSearchParam("date");
  const date = isIsoDate(dateParam) ? dateParam : filters.filters.to;
  const q = useDayReplay(id, date, filters.apiFilters);
  const data = q.data;
  const back = { href: `/field-team/${id}${filters.linkQuery}`, label: t("replay.backToOfficer") };

  const header = (
    <PageHeader
      title={data ? t("replay.titleFor", { name: data.officer_name }) : t("replay.title")}
      back={back}
      subtitle={<span className="tnum">{formatDay(date)}</span>}
      actions={
        <label className="flex flex-col gap-1 text-small font-semibold text-text-secondary">
          {t("replay.date")}
          <input
            type="date"
            value={date}
            max={filters.filters.to}
            onChange={(e) => e.target.value && setDate(e.target.value)}
            className="tnum h-10 rounded-input border border-border bg-surface px-3 text-body text-text"
            data-testid="replay-date"
          />
        </label>
      }
    />
  );

  if (q.error)
    return (
      <>
        {header}
        <div data-testid="replay-forbidden">
          <ProblemState
            error={q.error}
            onRetry={() => void q.refetch()}
            forbiddenHelp={t("replay.forbiddenHelp")}
          />
        </div>
      </>
    );
  if (!data)
    return (
      <>
        {header}
        <div className="grid grid-cols-1 gap-4 xl:grid-cols-[1fr_380px]">
          <SectionSkeleton height="h-[480px]" />
          <SectionSkeleton height="h-[480px]" />
        </div>
      </>
    );
  if (data.points.length === 0 && data.timeline.length === 0)
    return (
      <>
        {header}
        <EmptyState title={t("replay.emptyTitle")} help={t("replay.emptyHelp")} />
      </>
    );
  return (
    <>
      {header}
      <ReplayBody key={`${data.officer_id}-${data.date}`} data={data} />
    </>
  );
}

function eventLabel(e: TimelineEvent, visits: Map<string, ReplayVisit>, t: TFunction): string {
  const d = (e.detail ?? {}) as Record<string, unknown>;
  const v = e.ref_id ? visits.get(e.ref_id) : undefined;
  const farmer = v?.farmer_name ?? String(d.farmer_name ?? "");
  const minutes = typeof d.duration_s === "number" ? formatSeconds(d.duration_s) : "";
  switch (e.type) {
    case "duty_start":
      return t("replay.event.dutyStart");
    case "duty_end":
      return t("replay.event.dutyEnd");
    case "visit_checkin":
      return t("replay.event.checkin", { farmer });
    case "visit_checkout":
      return t("replay.event.checkout", { farmer });
    case "stop":
      return t("replay.event.stop", { duration: minutes });
    case "gap_start":
      return t("replay.event.gapStart", { duration: minutes });
    case "gap_end":
      return t("replay.event.gapEnd");
    default:
      return e.type;
  }
}

function gapReason(reason: unknown, t: TFunction): string {
  return typeof reason === "string" && reason.trim() ? reason : t("replay.noReason");
}

function ReplayBody({ data }: { data: DayReplayOut }) {
  const t = useT();
  const pb = React.useMemo(() => buildPlayback(data), [data]);
  const visits = React.useMemo(() => new Map(data.visits.map((v) => [v.id, v])), [data.visits]);
  const [value, setValue] = React.useState(0);
  const [playing, setPlaying] = React.useState(false);
  const [selected, setSelected] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!playing) return;
    const h = setInterval(() => {
      setValue((v) => {
        if (v + STEP >= SLIDER_MAX) {
          setPlaying(false);
          return SLIDER_MAX;
        }
        return v + STEP;
      });
    }, TICK_MS);
    return () => clearInterval(h);
  }, [playing]);

  const now = pb ? sliderToTime(pb, value) : 0;
  const position = pb ? positionAt(pb, now) : null;
  const activeIdx = pb ? activeTimelineIndex(pb, now) : -1;
  const activeEvent = activeIdx >= 0 ? data.timeline[activeIdx] : undefined;
  const autoVisit =
    activeEvent && (activeEvent.type === "visit_checkin" || activeEvent.type === "visit_checkout")
      ? (activeEvent.ref_id ?? null)
      : null;
  const visitId = selected ?? autoVisit;
  const visit = visitId ? visits.get(visitId) : undefined;

  const listRef = React.useRef<HTMLOListElement>(null);
  React.useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>('[data-active="true"]');
    el?.scrollIntoView?.({ block: "nearest" });
  }, [activeIdx]);

  const gapLabel = React.useCallback(
    (reason: string | null, durationS: number) =>
      t("replay.gapTooltip", { duration: formatSeconds(durationS), reason: gapReason(reason, t) }),
    [t],
  );
  const visitLabel = React.useCallback(
    (v: ReplayVisit) =>
      t("replay.visitTooltip", {
        farmer: v.farmer_name,
        status: t(`visitStatus.${visitStatusKey(v.status)}`),
        time: formatTimeIst(v.checkin_at),
      }),
    [t],
  );
  const stopLabel = React.useCallback(
    (s: number) => t("replay.event.stop", { duration: formatSeconds(s) }),
    [t],
  );

  const jumpTo = (e: TimelineEvent) => {
    if (!pb) return;
    setPlaying(false);
    setValue(timeToSlider(pb, Date.parse(e.ts)));
    if (e.ref_id && visits.has(e.ref_id)) setSelected(e.ref_id);
  };

  const exportCsv = () => {
    const cols: CsvColumn<TimelineEvent>[] = [
      { header: t("replay.csv.time"), value: (e) => formatTimeIst(e.ts) },
      { header: t("replay.csv.event"), value: (e) => eventLabel(e, visits, t) },
      {
        header: t("replay.csv.detail"),
        value: (e) => {
          const v = e.ref_id ? visits.get(e.ref_id) : undefined;
          if (v) return `${t(`visitStatus.${visitStatusKey(v.status)}`)} ${v.score ?? ""}`.trim();
          if (e.type === "gap_start")
            return gapReason((e.detail as Record<string, unknown>)?.reason, t);
          return "";
        },
      },
    ];
    downloadCsv(csvFilename(`replay-${data.officer_name}`, data.date), cols, data.timeline);
  };

  const unresolvedGaps = data.gaps.filter((g) => !g.reason).length;

  return (
    <>
      <section
        aria-label={t("replay.summary")}
        className="grid grid-cols-2 gap-3 md:grid-cols-5"
        data-testid="replay-summary"
      >
        <StatTile label={t("replay.km")} value={formatDecimal(data.km, 1)} />
        <StatTile label={t("replay.visits")} value={data.visits.length} />
        <StatTile
          label={t("replay.verified")}
          value={data.visits.filter((v) => v.status === "verified").length}
        />
        <StatTile label={t("replay.stops")} value={data.stops.length} />
        <StatTile label={t("replay.gaps")} value={data.gaps.length} />
      </section>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1fr)_380px]">
        <div className="flex min-w-0 flex-col gap-3">
          <ReplayMap
            replay={data}
            position={position}
            activeVisitId={visitId}
            onSelectVisit={(vid) => setSelected(vid)}
            gapLabel={gapLabel}
            visitLabel={visitLabel}
            stopLabel={stopLabel}
            attribution={t("map.attribution")}
            label={t("replay.mapLabel")}
          />
          <MapLegend />
          <div
            className="flex flex-wrap items-center gap-3 rounded-card border border-border bg-surface p-3"
            data-testid="playback"
          >
            <AppButton
              variant="secondary"
              size="M"
              icon={playing ? <Pause /> : <Play />}
              onClick={() => {
                if (!playing && value >= SLIDER_MAX) setValue(0);
                setPlaying((p) => !p);
              }}
              disabled={!pb}
            >
              {playing ? t("replay.pause") : t("replay.play")}
            </AppButton>
            <label className="flex min-w-[200px] flex-1 items-center gap-3">
              <span className="sr-only">{t("replay.slider")}</span>
              <input
                type="range"
                min={0}
                max={SLIDER_MAX}
                step={1}
                value={value}
                onChange={(e) => {
                  setPlaying(false);
                  setSelected(null);
                  setValue(Number(e.target.value));
                }}
                aria-valuetext={pb ? formatTimeIst(new Date(now).toISOString()) : undefined}
                className="w-full accent-primary"
                data-testid="replay-slider"
              />
            </label>
            <span
              className="tnum w-14 text-right text-body font-semibold"
              data-testid="replay-clock"
            >
              {pb ? formatTimeIst(new Date(now).toISOString()) : "—"}
            </span>
            {position?.inGap ? (
              <Badge variant="danger" data-testid="in-gap">
                {t("replay.inGap")}
              </Badge>
            ) : null}
          </div>
          {data.gaps.length ? (
            <Section title={t("replay.gapsTitle")} testId="replay-gaps">
              <ul className="flex flex-col gap-1 text-body">
                {data.gaps.map((g) => (
                  <li
                    key={g.start}
                    className="flex flex-wrap items-center gap-2"
                    data-testid="replay-gap-item"
                  >
                    <span className="tnum font-semibold">
                      {formatTimeIst(g.start)}–{formatTimeIst(g.end)}
                    </span>
                    <span className="text-text-secondary">{formatSeconds(g.duration_s)}</span>
                    <span className={g.reason ? "text-text" : "text-warning"}>
                      {gapReason(g.reason, t)}
                    </span>
                  </li>
                ))}
              </ul>
              {unresolvedGaps ? (
                <p className="text-small text-text-muted">{t("replay.gapReasonNote")}</p>
              ) : null}
            </Section>
          ) : null}
        </div>

        <aside className="flex min-w-0 flex-col gap-3" aria-label={t("replay.timeline")}>
          <Section
            title={t("replay.timeline")}
            testId="replay-timeline"
            actions={
              <AppButton variant="tertiary" size="M" onClick={exportCsv}>
                {t("common.export")}
              </AppButton>
            }
          >
            <ol ref={listRef} className="flex max-h-[360px] flex-col gap-1 overflow-y-auto pr-1">
              {data.timeline.map((e, i) => {
                const active = i === activeIdx;
                const v = e.ref_id ? visits.get(e.ref_id) : undefined;
                const isGap = e.type === "gap_start";
                return (
                  <li key={`${e.ts}-${e.type}-${i}`}>
                    <button
                      type="button"
                      onClick={() => jumpTo(e)}
                      data-active={active}
                      aria-current={active ? "step" : undefined}
                      data-testid="timeline-item"
                      data-type={e.type}
                      className={cn(
                        "flex w-full items-start gap-2 rounded-input border px-2 py-1.5 text-left text-small",
                        active
                          ? "border-primary bg-primary-container"
                          : "border-transparent hover:bg-background",
                      )}
                    >
                      <span className="tnum w-11 shrink-0 font-semibold text-text">
                        {formatTimeIst(e.ts)}
                      </span>
                      <span
                        aria-hidden="true"
                        className="mt-1 size-2.5 shrink-0 rounded-pill"
                        style={{
                          background: v
                            ? VISIT_COLOR[v.colour]
                            : isGap || e.type === "gap_end"
                              ? "var(--color-danger)"
                              : "var(--color-text-muted)",
                        }}
                      />
                      <span className="flex min-w-0 flex-col">
                        <span className="text-text">{eventLabel(e, visits, t)}</span>
                        {isGap ? (
                          <span className="text-text-muted">
                            {gapReason(
                              (e.detail as Record<string, unknown> | undefined)?.reason,
                              t,
                            )}
                          </span>
                        ) : null}
                        {v && e.type === "visit_checkin" ? (
                          <span className="text-text-muted">
                            {t(`visitStatus.${visitStatusKey(v.status)}`)}
                          </span>
                        ) : null}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ol>
          </Section>
          <Section title={t("replay.visitDetail")} testId="visit-detail">
            {visit ? (
              <VisitDetail visit={visit} />
            ) : (
              <p className="text-small text-text-muted">{t("replay.pickVisit")}</p>
            )}
          </Section>
        </aside>
      </div>
    </>
  );
}

function VisitDetail({ visit }: { visit: ReplayVisit }) {
  const t = useT();
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Link
          href={`/farmers/${visit.farmer_id}`}
          className="text-body font-semibold text-text hover:text-primary"
        >
          {visit.farmer_name}
        </Link>
        {visit.score === null ? (
          <Badge variant="neutral">{t("visitStatus.open")}</Badge>
        ) : (
          <VisitScoreBadge score={visit.score} />
        )}
      </div>
      <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-small">
        <dt className="text-text-muted">{t("replay.purpose")}</dt>
        <dd>{t(`purpose.${purposeKey(visit.purpose)}`)}</dd>
        <dt className="text-text-muted">{t("replay.checkin")}</dt>
        <dd className="tnum">{formatTimeIst(visit.checkin_at)}</dd>
        <dt className="text-text-muted">{t("replay.checkout")}</dt>
        <dd className="tnum">{formatTimeIst(visit.checkout_at)}</dd>
        <dt className="text-text-muted">{t("replay.duration")}</dt>
        <dd className="tnum">{formatSeconds(visit.duration_s)}</dd>
        <dt className="text-text-muted">{t("replay.geofence")}</dt>
        <dd>
          {visit.geofence_result === "inside"
            ? t("replay.geofenceInside")
            : t("replay.geofenceOutside")}
        </dd>
        <dt className="text-text-muted">{t("replay.photos")}</dt>
        <dd className="tnum">{visit.photos}</dd>
      </dl>
      <ProofChecklist items={visit.proof} />
    </div>
  );
}

function MapLegend() {
  const t = useT();
  const items = [
    { label: t("visitStatus.verified"), color: VISIT_COLOR.green, dot: true },
    { label: t("visitStatus.partial"), color: VISIT_COLOR.amber, dot: true },
    { label: t("visitStatus.unverified"), color: VISIT_COLOR.red, dot: true },
    { label: t("replay.legend.stop"), color: "var(--color-info)", dot: true },
    { label: t("replay.legend.track"), color: "var(--color-text)", dot: false },
    { label: t("replay.legend.gap"), color: "var(--color-danger)", dot: false, dashed: true },
    { label: t("replay.legend.position"), color: "var(--color-primary)", dot: true },
  ];
  return (
    <ul
      className="flex flex-wrap gap-x-4 gap-y-1 text-small text-text-secondary"
      aria-label={t("replay.legend.title")}
    >
      {items.map((i) => (
        <li key={i.label} className="flex items-center gap-1.5">
          {i.dot ? (
            <span
              aria-hidden="true"
              className="inline-block size-2.5 rounded-pill"
              style={{ background: i.color }}
            />
          ) : (
            <span
              aria-hidden="true"
              className="inline-block w-4"
              style={{ borderTop: `3px ${i.dashed ? "dashed" : "solid"} ${i.color}` }}
            />
          )}
          {i.label}
        </li>
      ))}
    </ul>
  );
}
