"use client";

/**
 * C31 Farmer 360 (WC-003 acceptance "profile reflects latest sync"; AN-004): the API reads the
 * live tables on every request (no cache beyond 30 s client staleness). Profile header with
 * consent status, summary, then tabs (in the URL as `tab`): farms (map with polygons + crops
 * with stages), visits, orders, khata (balance, buckets, limits), consent history, app usage.
 */
import * as React from "react";
import Link from "next/link";
import { Camera } from "lucide-react";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { EmptyState } from "@/components/ds/EmptyState";
import { StatTile } from "@/components/ds/StatTile";
import { Tabs } from "@/components/ds/Tabs";
import { VisitScoreBadge } from "@/components/ds/VisitScoreBadge";
import { BarCompare, CHART } from "@/components/analytics/charts";
import { InfoTip } from "@/components/analytics/InfoTip";
import { FarmsMap } from "@/components/analytics/maps";
import { AnalyticsGate, PageHeader, Section, SectionSkeleton } from "@/components/analytics/Page";
import { ProblemState } from "@/components/analytics/ProblemState";
import { AppButton } from "@/components/ds/AppButton";
import { Badge } from "@/components/ui/badge";
import { OVERDUE_BUCKETS, type Farmer360Out } from "@/lib/analytics";
import {
  formatDay,
  formatDecimal,
  formatInrOrDash,
  formatInrShort,
  purposeKey,
  stageLabel,
  visitStatusKey,
} from "@/lib/analytics-format";
import { csvFilename, downloadCsv, paiseToRupees, type CsvColumn } from "@/lib/csv";
import { formatDateIst, formatDateTimeIst } from "@/lib/format";
import { useFarmer360, useFilterOptions } from "@/lib/hooks/analytics";
import { useAnalyticsFilters, useSearchParam } from "@/lib/hooks/use-analytics-filters";
import { useT } from "@/lib/i18n-client";

const CHANNELS = ["pos", "field", "app", "whatsapp", "call"] as const;
const channelKey = (c: string): (typeof CHANNELS)[number] | "other" =>
  (CHANNELS as readonly string[]).includes(c) ? (c as (typeof CHANNELS)[number]) : "other";
const ORDER_STATUSES = [
  "draft",
  "placed",
  "confirmed",
  "handed_over",
  "delivered",
  "cancelled",
  "returned",
] as const;
const orderStatusKey = (s: string): (typeof ORDER_STATUSES)[number] | "other" =>
  (ORDER_STATUSES as readonly string[]).includes(s)
    ? (s as (typeof ORDER_STATUSES)[number])
    : "other";

const TABS = ["farms", "visits", "orders", "khata", "consent", "app"] as const;
type Tab = (typeof TABS)[number];

export function Farmer360View({ id }: { id: string }) {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C31">
      <AnalyticsGate path="/farmers" title={t("farmer360.title")}>
        <Farmer360 id={id} />
      </AnalyticsGate>
    </div>
  );
}

type F = Farmer360Out;

function Farmer360({ id }: { id: string }) {
  const t = useT();
  const filters = useAnalyticsFilters();
  const q = useFarmer360(id, filters.apiFilters);
  const opts = useFilterOptions();
  const [tabParam, setTab] = useSearchParam("tab");
  const tab: Tab = (TABS as readonly string[]).includes(tabParam ?? "")
    ? (tabParam as Tab)
    : "farms";
  const data = q.data;
  const back = { href: `/farmers${filters.linkQuery}`, label: t("farmers.backToList") };

  if (q.error)
    return (
      <>
        <PageHeader title={t("farmer360.title")} back={back} />
        <ProblemState error={q.error} onRetry={() => void q.refetch()} />
      </>
    );
  if (!data)
    return (
      <>
        <PageHeader title={t("farmer360.title")} back={back} />
        <SectionSkeleton height="h-24" />
        <SectionSkeleton height="h-96" />
      </>
    );

  const p = data.profile;
  const storeName = opts.storeName(p.store_id);

  const exportTab = () => {
    const base = `farmer-${p.name}-${tab}`;
    const file = csvFilename(base);
    switch (tab) {
      case "visits":
        return downloadCsv(file, visitCsv(t), data.visits);
      case "orders":
        return downloadCsv(file, orderCsv(t), data.orders);
      case "consent":
        return downloadCsv(file, consentCsv(t), data.consent.history);
      case "khata":
        return downloadCsv(
          file,
          [
            {
              header: t("farmer360.khata.bucket"),
              value: (b: string) => t(`buckets.${b as (typeof OVERDUE_BUCKETS)[number]}`),
            },
            {
              header: t("farmer360.khata.amountRupees"),
              value: (b: string) => paiseToRupees(data.khata.overdue_buckets[b] ?? 0),
            },
          ],
          [...OVERDUE_BUCKETS],
        );
      default:
        return downloadCsv(
          file,
          cropCsv(t),
          data.farms.flatMap((f) => f.crop_plots.map((c) => ({ farm: f, plot: c }))),
        );
    }
  };

  return (
    <>
      <PageHeader
        title={p.name}
        back={back}
        subtitle={
          <span className="flex flex-wrap items-center gap-2" data-testid="farmer-header">
            <span>
              {p.village} · {p.district}
              {storeName ? ` · ${storeName}` : ""}
            </span>
            <span className="tnum">{p.phone}</span>
            <Badge
              variant={data.consent.current.data ? "success" : "danger"}
              data-testid="consent-data"
            >
              {data.consent.current.data
                ? t("farmer360.consent.dataGranted")
                : t("farmer360.consent.dataWithdrawn")}
            </Badge>
            <Badge
              variant={data.consent.current.marketing ? "success" : "neutral"}
              data-testid="consent-marketing"
            >
              {data.consent.current.marketing
                ? t("farmer360.consent.marketingGranted")
                : t("farmer360.consent.marketingWithdrawn")}
            </Badge>
            <Badge variant={data.active ? "default" : "neutral"}>
              {data.active ? t("farmer360.active") : t("farmer360.inactive")}
            </Badge>
            <Badge
              variant={
                data.khata.credit_risk === "high"
                  ? "danger"
                  : data.khata.credit_risk === "medium"
                    ? "warning"
                    : "success"
              }
              data-testid="credit-risk"
            >
              {t("farmer360.creditRisk", { level: t(`farmers.risk.${data.khata.credit_risk}`) })}
            </Badge>
            {data.churn_risk.at_risk ? (
              <Badge variant="warning" data-testid="churn-risk">
                {t("farmer360.churnRisk", { n: data.churn_risk.window_days })}
              </Badge>
            ) : null}
          </span>
        }
        actions={
          <AppButton variant="secondary" size="M" onClick={exportTab}>
            {t("common.export")}
          </AppButton>
        }
      />
      <p className="text-small text-text-muted">
        {t("farmer360.registeredBy", {
          name: p.registered_by_name ?? t("common.none"),
          date: formatDateIst(p.created_at),
        })}{" "}
        · {t("farmer360.updatedAt", { date: formatDateTimeIst(p.updated_at) })}
      </p>

      <section
        aria-label={t("farmer360.summary")}
        className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6"
        data-testid="farmer-summary"
      >
        <div className="relative">
          <StatTile label={t("farmer360.ltv")} value={formatInrShort(data.ltv_paise)} />
          <InfoTip
            className="absolute right-3 top-3"
            name={t("farmer360.ltv")}
            text={t("kpiDefinitions.ltv")}
          />
        </div>
        <StatTile label={t("farmer360.balance")} value={formatInrShort(data.khata.balance_paise)} />
        <StatTile label={t("farmer360.overdue")} value={formatInrShort(data.khata.overdue_paise)} />
        <StatTile
          label={t("farmer360.lastVisit")}
          value={data.last_visit_at ? formatDateIst(data.last_visit_at) : t("farmers.never")}
        />
        <StatTile
          label={t("farmer360.lastPurchase")}
          value={data.last_purchase_at ? formatDateIst(data.last_purchase_at) : t("farmers.never")}
        />
        <StatTile label={t("farmer360.appSessions")} value={data.app_usage.sessions_last_60_days} />
      </section>
      <p className="text-small text-text-muted" data-testid="churn-note">
        {data.churn_risk.at_risk
          ? t("farmer360.churnNote", {
              purchase: data.churn_risk.days_since_last_purchase ?? 0,
              visit:
                data.churn_risk.days_since_last_visit === null
                  ? t("farmers.never")
                  : String(data.churn_risk.days_since_last_visit),
            })
          : t("farmer360.churnClear", { n: data.churn_risk.window_days })}
      </p>

      <Tabs<Tab>
        label={t("farmer360.tabsLabel")}
        value={tab}
        onValueChange={(v) => setTab(v === "farms" ? undefined : v, { replace: true })}
        items={[
          {
            value: "farms",
            label: t("farmer360.tabs.farms"),
            count: data.farms.length,
            content: <FarmsTab data={data} />,
          },
          {
            value: "visits",
            label: t("farmer360.tabs.visits"),
            count: data.visits.length,
            content: <VisitsTab data={data} />,
          },
          {
            value: "orders",
            label: t("farmer360.tabs.orders"),
            count: data.orders.length,
            content: <OrdersTab data={data} />,
          },
          { value: "khata", label: t("farmer360.tabs.khata"), content: <KhataTab data={data} /> },
          {
            value: "consent",
            label: t("farmer360.tabs.consent"),
            content: <ConsentTab data={data} />,
          },
          { value: "app", label: t("farmer360.tabs.app"), content: <AppTab data={data} /> },
        ]}
      />
    </>
  );
}

type TF = ReturnType<typeof useT>;
type CropRow = { farm: F["farms"][number]; plot: F["farms"][number]["crop_plots"][number] };

const cropCsv = (t: TF): CsvColumn<CropRow>[] => [
  { header: t("farmer360.farms.farm"), value: (r) => r.farm.name ?? r.farm.survey_no ?? "" },
  { header: t("farmer360.farms.crop"), value: (r) => r.plot.crop_name },
  { header: t("farmer360.farms.variety"), value: (r) => r.plot.variety ?? "" },
  { header: t("farmer360.farms.stage"), value: (r) => stageLabel(r.plot.stage, t) },
  { header: t("farmer360.farms.sown"), value: (r) => formatDay(r.plot.sowing_date) },
  { header: t("farmer360.farms.harvest"), value: (r) => formatDay(r.plot.expected_harvest) },
  { header: t("farmer360.farms.acres"), value: (r) => r.plot.area_acres },
];

const visitCsv = (t: TF): CsvColumn<F["visits"][number]>[] => [
  { header: t("fieldTeam.visits.when"), value: (v) => formatDateTimeIst(v.checkin_at) },
  { header: t("farmer360.visits.officer"), value: (v) => v.officer_name },
  { header: t("fieldTeam.visits.purpose"), value: (v) => t(`purpose.${purposeKey(v.purpose)}`) },
  {
    header: t("farmer360.visits.status"),
    value: (v) => t(`visitStatus.${visitStatusKey(v.status)}`),
  },
  { header: t("fieldTeam.visits.score"), value: (v) => v.score },
  {
    header: t("farmer360.visits.confirmed"),
    value: (v) => (v.confirmed ? t("common.yes") : t("common.no")),
  },
];

const orderCsv = (t: TF): CsvColumn<F["orders"][number]>[] => [
  {
    header: t("farmer360.orders.placed"),
    value: (o) => (o.placed_at ? formatDateTimeIst(o.placed_at) : ""),
  },
  { header: t("farmer360.orders.invoice"), value: (o) => o.invoice_no ?? "" },
  {
    header: t("farmer360.orders.channel"),
    value: (o) => t(`orderChannel.${channelKey(o.channel)}`),
  },
  {
    header: t("farmer360.orders.status"),
    value: (o) => t(`orderStatus.${orderStatusKey(o.status)}`),
  },
  { header: t("farmer360.orders.lines"), value: (o) => o.lines },
  { header: t("farmer360.orders.totalRupees"), value: (o) => paiseToRupees(o.total_paise) },
];

const consentCsv = (t: TF): CsvColumn<F["consent"]["history"][number]>[] => [
  { header: t("farmer360.consent.when"), value: (c) => formatDateTimeIst(c.at) },
  {
    header: t("farmer360.consent.purpose"),
    value: (c) =>
      c.purpose === "marketing" ? t("farmer360.consent.marketing") : t("farmer360.consent.data"),
  },
  {
    header: t("farmer360.consent.state"),
    value: (c) => (c.granted ? t("farmer360.consent.granted") : t("farmer360.consent.withdrawn")),
  },
  { header: t("farmer360.consent.version"), value: (c) => c.version },
  {
    header: t("farmer360.consent.channel"),
    value: (c) => t(`orderChannel.${channelKey(c.channel)}`),
  },
];

function FarmsTab({ data }: { data: F }) {
  const t = useT();
  const rows: CropRow[] = data.farms.flatMap((farm) =>
    farm.crop_plots.map((plot) => ({ farm, plot })),
  );
  const describe = React.useCallback(
    (farm: F["farms"][number]) =>
      t("farmer360.farms.tooltip", {
        name: farm.name ?? farm.survey_no ?? "",
        acres: formatDecimal(farm.area_acres, 1),
      }),
    [t],
  );
  if (data.farms.length === 0)
    return (
      <EmptyState title={t("farmer360.farms.emptyTitle")} help={t("farmer360.farms.emptyHelp")} />
    );
  const columns: DataTableColumn<CropRow>[] = [
    {
      id: "farm",
      header: t("farmer360.farms.farm"),
      cell: (r) => `${r.farm.name ?? ""} ${r.farm.survey_no ? `(${r.farm.survey_no})` : ""}`.trim(),
    },
    { id: "crop", header: t("farmer360.farms.crop"), accessor: (r) => r.plot.crop_name },
    {
      id: "variety",
      header: t("farmer360.farms.variety"),
      cell: (r) => r.plot.variety ?? t("common.none"),
    },
    {
      id: "stage",
      header: t("farmer360.farms.stage"),
      cell: (r) => <Badge variant="neutral">{stageLabel(r.plot.stage, t)}</Badge>,
    },
    { id: "sown", header: t("farmer360.farms.sown"), cell: (r) => formatDay(r.plot.sowing_date) },
    {
      id: "harvest",
      header: t("farmer360.farms.harvest"),
      cell: (r) => formatDay(r.plot.expected_harvest),
    },
    {
      id: "acres",
      header: t("farmer360.farms.acres"),
      numeric: true,
      cell: (r) => formatDecimal(r.plot.area_acres, 1),
    },
    {
      id: "soil",
      header: t("farmer360.farms.soilIrrigation"),
      cell: (r) => [r.farm.soil, r.farm.irrigation].filter(Boolean).join(" · ") || t("common.none"),
    },
  ];
  return (
    <div className="flex flex-col gap-4 pt-3" data-testid="tab-farms">
      <FarmsMap
        farms={data.farms}
        describe={describe}
        attribution={t("map.attribution")}
        label={t("farmer360.farms.mapLabel")}
      />
      <DataTable
        caption={t("farmer360.farms.crops")}
        columns={columns}
        rows={rows}
        rowKey={(r) => r.plot.id}
      />
    </div>
  );
}

function VisitsTab({ data }: { data: F }) {
  const t = useT();
  const withPhotos = data.visits.some((v) => typeof v.photos === "number");
  const columns: DataTableColumn<F["visits"][number]>[] = [
    {
      id: "when",
      header: t("fieldTeam.visits.when"),
      accessor: (v) => v.checkin_at,
      cell: (v) => formatDateTimeIst(v.checkin_at),
      sortable: true,
    },
    {
      id: "officer",
      header: t("farmer360.visits.officer"),
      cell: (v) => (
        <Link href={`/field-team/${v.officer_id}`} className="hover:text-primary">
          {v.officer_name}
        </Link>
      ),
    },
    {
      id: "purpose",
      header: t("fieldTeam.visits.purpose"),
      cell: (v) => t(`purpose.${purposeKey(v.purpose)}`),
    },
    {
      id: "stage",
      header: t("farmer360.visits.cropStage"),
      cell: (v) => stageLabel(v.crop_stage, t),
    },
    {
      id: "score",
      header: t("fieldTeam.visits.score"),
      accessor: (v) => v.score,
      sortable: true,
      cell: (v) =>
        v.score === null ? (
          <Badge variant="neutral">{t("visitStatus.open")}</Badge>
        ) : (
          <VisitScoreBadge score={v.score} size="sm" />
        ),
    },
    {
      id: "confirmed",
      header: t("farmer360.visits.confirmed"),
      cell: (v) => (v.confirmed ? t("common.yes") : t("common.no")),
    },
    ...(withPhotos
      ? [
          {
            id: "photos",
            header: t("farmer360.visits.photos"),
            numeric: true,
            cell: (v: F["visits"][number]) => (
              <span className="inline-flex items-center gap-1">
                <Camera className="size-4 text-text-muted" aria-hidden="true" />
                {v.photos ?? 0}
              </span>
            ),
          },
        ]
      : []),
  ];
  return (
    <div className="flex flex-col gap-4 pt-3" data-testid="tab-visits">
      <DataTable
        caption={t("farmer360.tabs.visits")}
        columns={columns}
        rows={data.visits}
        rowKey={(v) => v.id}
        emptyTitle={t("farmer360.visits.emptyTitle")}
        emptyHelp={t("farmer360.visits.emptyHelp")}
      />
      <Section title={t("farmer360.diagnoses.title")} testId="diagnoses">
        {data.diagnoses.length === 0 ? (
          <EmptyState
            illustration={<Camera className="size-6" aria-hidden="true" />}
            title={t("farmer360.diagnoses.emptyTitle")}
            help={t("farmer360.diagnoses.emptyHelp")}
          />
        ) : (
          <ul className="text-body">
            {data.diagnoses.map((d, i) => (
              <li key={i}>{String(d.problem ?? d.label ?? "")}</li>
            ))}
          </ul>
        )}
      </Section>
    </div>
  );
}

function OrdersTab({ data }: { data: F }) {
  const t = useT();
  const opts = useFilterOptions();
  const columns: DataTableColumn<F["orders"][number]>[] = [
    {
      id: "placed",
      header: t("farmer360.orders.placed"),
      accessor: (o) => o.placed_at,
      sortable: true,
      cell: (o) => (o.placed_at ? formatDateTimeIst(o.placed_at) : t("common.none")),
    },
    {
      id: "invoice",
      header: t("farmer360.orders.invoice"),
      cell: (o) => o.invoice_no ?? t("common.none"),
    },
    {
      id: "store",
      header: t("farmer360.orders.store"),
      cell: (o) => opts.storeName(o.store_id) ?? t("common.none"),
    },
    {
      id: "channel",
      header: t("farmer360.orders.channel"),
      cell: (o) => <Badge variant="outline">{t(`orderChannel.${channelKey(o.channel)}`)}</Badge>,
    },
    {
      id: "status",
      header: t("farmer360.orders.status"),
      cell: (o) => t(`orderStatus.${orderStatusKey(o.status)}`),
    },
    { id: "lines", header: t("farmer360.orders.lines"), numeric: true, accessor: (o) => o.lines },
    {
      id: "total",
      header: t("farmer360.orders.total"),
      numeric: true,
      accessor: (o) => o.total_paise,
      sortable: true,
      cell: (o) => formatInrOrDash(o.total_paise),
    },
  ];
  return (
    <div className="pt-3" data-testid="tab-orders">
      <DataTable
        caption={t("farmer360.tabs.orders")}
        columns={columns}
        rows={data.orders}
        rowKey={(o) => o.id}
        emptyTitle={t("farmer360.orders.emptyTitle")}
        emptyHelp={t("farmer360.orders.emptyHelp")}
      />
    </div>
  );
}

function KhataTab({ data }: { data: F }) {
  const t = useT();
  const opts = useFilterOptions();
  const k = data.khata;
  return (
    <div className="flex flex-col gap-4 pt-3" data-testid="tab-khata">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatTile label={t("farmer360.balance")} value={formatInrOrDash(k.balance_paise)} />
        <StatTile label={t("farmer360.overdue")} value={formatInrOrDash(k.overdue_paise)} />
        <StatTile label={t("farmer360.khata.nextDue")} value={formatDay(k.next_due_date)} />
        <StatTile
          label={t("farmer360.khata.lastPayment")}
          value={k.last_payment_at ? formatDateIst(k.last_payment_at) : t("common.none")}
        />
      </div>
      <div className="flex flex-wrap items-center gap-2 text-small">
        <span className="text-text-secondary">{t("farmers.columns.risk")}</span>
        <Badge
          variant={
            k.credit_risk === "high" ? "danger" : k.credit_risk === "medium" ? "warning" : "success"
          }
        >
          {t(`farmers.risk.${k.credit_risk}`)}
        </Badge>
        {k.credit_limits.map((l) => (
          <span key={l.store_id} className="text-text-secondary">
            {t("farmer360.khata.limit", {
              store: opts.storeName(l.store_id) ?? t("common.none"),
              amount: formatInrOrDash(l.limit_paise),
            })}
          </span>
        ))}
      </div>
      <Section
        title={t("farmer360.khata.buckets")}
        info={
          <InfoTip name={t("kpiNames.creditOverdue")} text={t("kpiDefinitions.creditOverdue")} />
        }
      >
        <BarCompare
          label={t("farmer360.khata.buckets")}
          data={OVERDUE_BUCKETS.map((b) => ({
            bucket: t(`buckets.${b}`),
            value: k.overdue_buckets[b] ?? 0,
          }))}
          categoryKey="bucket"
          layout="horizontal"
          series={[{ key: "value", label: t("farmer360.overdue"), color: CHART.bad }]}
          valueFormat={formatInrShort}
          height={200}
        />
      </Section>
      <p className="text-small text-text-muted">{t("farmer360.khata.entriesNote")}</p>
    </div>
  );
}

function ConsentTab({ data }: { data: F }) {
  const t = useT();
  const columns: DataTableColumn<F["consent"]["history"][number]>[] = [
    {
      id: "at",
      header: t("farmer360.consent.when"),
      accessor: (c) => c.at,
      sortable: true,
      cell: (c) => formatDateTimeIst(c.at),
    },
    {
      id: "purpose",
      header: t("farmer360.consent.purpose"),
      cell: (c) =>
        c.purpose === "marketing" ? t("farmer360.consent.marketing") : t("farmer360.consent.data"),
    },
    {
      id: "state",
      header: t("farmer360.consent.state"),
      cell: (c) => (
        <Badge variant={c.granted ? "success" : "danger"}>
          {c.granted ? t("farmer360.consent.granted") : t("farmer360.consent.withdrawn")}
        </Badge>
      ),
    },
    { id: "version", header: t("farmer360.consent.version"), accessor: (c) => c.version },
    {
      id: "channel",
      header: t("farmer360.consent.channel"),
      cell: (c) => t(`orderChannel.${channelKey(c.channel)}`),
    },
  ];
  return (
    <div className="pt-3" data-testid="tab-consent">
      <DataTable
        caption={t("farmer360.tabs.consent")}
        columns={columns}
        rows={data.consent.history}
        rowKey={(c) => `${c.purpose}-${c.at}`}
      />
    </div>
  );
}

function AppTab({ data }: { data: F }) {
  const t = useT();
  const a = data.app_usage;
  return (
    <div className="flex flex-col gap-3 pt-3" data-testid="tab-app">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatTile
          label={t("farmer360.app.hasLogin")}
          value={a.has_app_login ? t("common.yes") : t("common.no")}
        />
        <StatTile
          label={t("farmer360.app.lastSession")}
          value={a.last_session_at ? formatDateIst(a.last_session_at) : t("common.none")}
        />
        <StatTile label={t("farmer360.app.sessions")} value={a.sessions_last_60_days} />
        <StatTile label={t("farmer360.ltv")} value={formatInrShort(data.ltv_paise)} />
        <StatTile label={t("farmer360.spend")} value={formatInrShort(data.spend_paise)} />
        <StatTile label={t("farmer360.orderCount")} value={data.churn_risk.orders} />
      </div>
      <p className="text-small text-text-muted">{t("farmer360.app.proxyNote")}</p>
    </div>
  );
}
