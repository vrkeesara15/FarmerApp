"use client";

/**
 * C32 farmer segments (AN-004): the WC-008 segment builder on its own screen, reached from the
 * C30 directory.
 *
 * The count next to the builder is the consented reach; the preview below it is the AN-004
 * breakdown of the same farmers — by crop, district, crop stage, acreage band, spend band, last
 * visit, consent and app usage — as bar comparisons (SPEC 13.4: no pies). Filters stay in the
 * URL (AN-011), so a segment previewed for one cluster can be shared as a link.
 *
 * A segment is **saved server-side** (`POST /v1/analytics/segments`) and "Create a campaign"
 * carries its id, so C81 loads the definition from the API instead of the browser's session
 * storage, and a campaign keeps its own copy of what it was sent to.
 */
import * as React from "react";
import { useRouter } from "next/navigation";
import { Megaphone, Save, Trash2, Users } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { StatTile } from "@/components/ds/StatTile";
import { AnalyticsFilterBar } from "@/components/analytics/AnalyticsFilterBar";
import { BarCompare, CHART, CHART_SERIES } from "@/components/analytics/charts";
import { PageHeader, Section, SectionSkeleton } from "@/components/analytics/Page";
import { ProblemState } from "@/components/analytics/ProblemState";
import { RoleGate, SessionGate } from "@/components/admin/common";
import type { SavedSegment, SegmentFacet, SegmentPreviewOut } from "@/lib/analytics";
import { formatInrShort } from "@/lib/analytics-format";
import { formatDateTimeIst, formatNumber } from "@/lib/format";
import { CAMPAIGN_WRITE_ROLES, isEmptySegment, type CampaignSegment } from "@/lib/campaigns";
import { useAnalyticsFilters } from "@/lib/hooks/use-analytics-filters";
import { useSavedSegments, useSaveSegment, useSegmentPreview } from "@/lib/hooks/analytics";
import { FARMER_ROLES } from "@/lib/nav";
import type { MessageKey } from "@/lib/i18n";
import { useT } from "@/lib/i18n-client";
import { useSession } from "@/lib/session-context";
import { SegmentBuilder } from "./SegmentBuilder";

export function SegmentsView() {
  return (
    <div className="flex flex-col gap-4" data-screen="C32">
      <SessionGate>
        <RoleGate roles={FARMER_ROLES}>
          <Segments />
        </RoleGate>
      </SessionGate>
    </div>
  );
}

const ACREAGE_LABEL = (key: string): MessageKey => `segments.acreage.${key}` as MessageKey;
const SPEND_LABEL = (key: string): MessageKey => `segments.spend.${key}` as MessageKey;
const VISIT_LABEL = (key: string): MessageKey => `farmers.lastVisitWindow.${key}` as MessageKey;

function Segments() {
  const t = useT();
  const router = useRouter();
  const { role } = useSession();
  const filters = useAnalyticsFilters();
  const [segment, setSegment] = React.useState<CampaignSegment>({});
  const [name, setName] = React.useState("");
  const [editing, setEditing] = React.useState<SavedSegment | null>(null);
  const [error, setError] = React.useState<string | undefined>();
  const empty = isEmptySegment(segment);
  const canCampaign = !!role && CAMPAIGN_WRITE_ROLES.includes(role);

  const saved = useSavedSegments();
  const preview = useSegmentPreview(filters.apiFilters, segment, !empty);
  const mutations = useSaveSegment(filters.apiFilters);

  const load = (row: SavedSegment) => {
    setSegment(row.definition as CampaignSegment);
    setName(row.name);
    setEditing(row);
    setError(undefined);
  };

  const save = async () => {
    setError(undefined);
    const trimmed = name.trim();
    if (trimmed.length < 3) return setError(t("segments.nameTooShort"));
    try {
      if (editing)
        await mutations.update.mutateAsync({ id: editing.id, name: trimmed, definition: segment });
      else {
        const row = await mutations.create.mutateAsync({
          name: trimmed,
          description: null,
          definition: segment,
        });
        setEditing(row);
      }
    } catch {
      setError(t("segments.saveFailed"));
    }
  };

  const openCampaign = async () => {
    setError(undefined);
    let target = editing;
    if (!target) {
      const trimmed = name.trim() || t("segments.untitled");
      try {
        target = await mutations.create.mutateAsync({
          name: trimmed,
          description: null,
          definition: segment,
        });
      } catch {
        return setError(t("segments.saveFailed"));
      }
    }
    router.push(`/campaigns/new?segment=${encodeURIComponent(target.id)}`);
  };

  const savedColumns: DataTableColumn<SavedSegment>[] = [
    {
      id: "name",
      header: t("segments.column.name"),
      accessor: (s) => s.name,
      sortable: true,
      cell: (s) => (
        <span className="flex flex-col">
          <span className="font-semibold text-text">{s.name}</span>
          {s.description ? (
            <span className="text-small text-text-muted">{s.description}</span>
          ) : null}
        </span>
      ),
    },
    {
      id: "reach",
      header: t("segments.column.reach"),
      numeric: true,
      accessor: (s) => s.last_count ?? -1,
      sortable: true,
      cell: (s) => (s.last_count === null ? t("common.none") : formatNumber(s.last_count)),
    },
    {
      id: "updated",
      header: t("segments.column.updated"),
      accessor: (s) => s.updated_at,
      sortable: true,
      cell: (s) => formatDateTimeIst(s.updated_at),
    },
    {
      id: "actions",
      header: t("segments.column.actions"),
      cell: (s) => (
        <span className="flex flex-wrap gap-2">
          <AppButton variant="tertiary" onClick={() => load(s)} data-testid={`load-${s.id}`}>
            {t("segments.load")}
          </AppButton>
          {canCampaign ? (
            <AppButton
              variant="tertiary"
              onClick={() => void mutations.remove.mutateAsync(s.id)}
              data-testid={`delete-${s.id}`}
            >
              <Trash2 className="size-4" aria-hidden="true" />
              {t("segments.delete")}
            </AppButton>
          ) : null}
        </span>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title={t("segments.title")}
        subtitle={t("segments.subtitle")}
        back={{ href: `/farmers${filters.linkQuery}`, label: t("segments.back") }}
      />
      <AnalyticsFilterBar state={filters} hide={{ officer: true }} />

      <Section title={t("segments.saved")} testId="saved-segments">
        <DataTable
          caption={t("segments.saved")}
          columns={savedColumns}
          rows={saved.data?.items ?? []}
          rowKey={(s) => s.id}
          loading={saved.isLoading}
          emptyTitle={t("segments.savedEmptyTitle")}
          emptyHelp={t("segments.savedEmptyHelp")}
        />
      </Section>

      <SegmentBuilder
        value={segment}
        onChange={(next) => {
          setSegment(next);
          setEditing(null);
        }}
        error={error}
        actions={
          canCampaign ? (
            <>
              <label className="sr-only" htmlFor="segment-name">
                {t("segments.nameLabel")}
              </label>
              <input
                id="segment-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder={t("segments.namePlaceholder")}
                maxLength={120}
                className="h-10 min-w-56 rounded-input border border-border bg-surface px-3 text-body text-text focus:outline-none focus:ring-2 focus:ring-primary"
                data-testid="segment-name"
              />
              <AppButton
                variant="secondary"
                onClick={() => void save()}
                disabled={empty || mutations.create.isPending || mutations.update.isPending}
                data-testid="segment-save"
              >
                <Save className="size-4" aria-hidden="true" />
                {editing ? t("segments.update") : t("segments.save")}
              </AppButton>
              <AppButton
                onClick={() => void openCampaign()}
                disabled={empty}
                data-testid="segment-to-campaign"
              >
                <Megaphone className="size-4" aria-hidden="true" />
                {t("segments.createCampaign")}
              </AppButton>
            </>
          ) : null
        }
      />

      {empty ? null : preview.error ? (
        <ProblemState error={preview.error} onRetry={() => void preview.refetch()} />
      ) : preview.data ? (
        <Preview data={preview.data} />
      ) : (
        <SectionSkeleton />
      )}
    </>
  );
}

function Preview({ data }: { data: SegmentPreviewOut }) {
  const t = useT();
  const label = (facets: SegmentFacet[], to: (key: string) => MessageKey) =>
    facets.map((f) => ({ key: t(to(f.key)), count: f.count }));
  const plain = (facets: SegmentFacet[]) =>
    facets.slice(0, 10).map((f) => ({ key: f.key, count: f.count }));
  const bars = (rows: Array<{ key: string; count: number }>, title: string, colour: string) => (
    <BarCompare
      label={title}
      data={rows}
      categoryKey="key"
      layout="horizontal"
      series={[{ key: "count", label: t("segments.farmers"), color: colour }]}
      valueFormat={formatNumber}
      height={Math.max(180, rows.length * 34)}
    />
  );

  return (
    <div className="flex flex-col gap-4" data-testid="segment-preview">
      <section
        aria-label={t("segments.preview")}
        className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5"
      >
        <StatTile label={t("segments.matched")} value={formatNumber(data.matched)} />
        <StatTile label={t("segments.consented")} value={formatNumber(data.consented)} />
        <StatTile label={t("segments.churnRisk")} value={formatNumber(data.churn_risk)} />
        <StatTile label={t("segments.ltv")} value={formatInrShort(data.ltv_paise)} />
        <StatTile label={t("segments.appUsers")} value={formatNumber(data.app_users)} />
      </section>
      <p className="text-small text-text-muted" data-testid="segment-preview-note">
        {t("segments.previewNote", {
          excluded: formatNumber(data.excluded_no_consent),
          days: data.churn_window_days,
        })}
      </p>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Section title={t("segments.byCrop")} testId="segment-by-crop">
          {bars(plain(data.by_crop), t("segments.byCrop"), CHART_SERIES[0])}
        </Section>
        <Section title={t("segments.byDistrict")} testId="segment-by-district">
          {bars(plain(data.by_district), t("segments.byDistrict"), CHART_SERIES[1])}
        </Section>
        <Section title={t("segments.byAcreage")} testId="segment-by-acreage">
          {bars(
            label(data.by_acreage_band, ACREAGE_LABEL),
            t("segments.byAcreage"),
            CHART_SERIES[2],
          )}
        </Section>
        <Section title={t("segments.bySpend")} testId="segment-by-spend">
          {bars(label(data.by_spend_band, SPEND_LABEL), t("segments.bySpend"), CHART.ownBrand)}
        </Section>
        <Section title={t("segments.byLastVisit")} testId="segment-by-visit">
          {bars(label(data.by_last_visit, VISIT_LABEL), t("segments.byLastVisit"), CHART.reference)}
        </Section>
        <Section title={t("segments.byStage")} testId="segment-by-stage">
          {bars(
            data.by_stage.map((f) => ({ key: t(`stage.${f.key}` as MessageKey), count: f.count })),
            t("segments.byStage"),
            CHART_SERIES[2],
          )}
        </Section>
      </div>

      <Section title={t("segments.consentAndApp")} testId="segment-consent">
        <div className="flex items-center gap-2 text-small text-text-secondary">
          <Users className="size-4 text-primary" aria-hidden="true" />
          {t("segments.consentSummary", {
            granted: formatNumber(data.consented),
            withheld: formatNumber(data.excluded_no_consent),
            app: formatNumber(data.app_users),
          })}
        </div>
        {bars(
          [
            ...data.by_consent.map((f) => ({
              key: t(`segments.consent.${f.key}` as MessageKey),
              count: f.count,
            })),
            ...data.by_app_usage.map((f) => ({
              key: t(`segments.app.${f.key}` as MessageKey),
              count: f.count,
            })),
          ],
          t("segments.consentAndApp"),
          CHART.good,
        )}
      </Section>
    </div>
  );
}
