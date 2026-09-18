"use client";

import * as React from "react";
import { Download, Flag, Home, Leaf, Plus, Store, Users } from "lucide-react";
import {
  AppButton,
  AppTextField,
  ConfidenceBand,
  DataTable,
  DateRangePicker,
  Dialog,
  EmptyState,
  ErrorState,
  FilterBar,
  FlagCard,
  KpiCard,
  OtpInput,
  OwnBrandBadge,
  SearchBar,
  SegmentedControl,
  SeverityBadge,
  SideNav,
  Skeleton,
  SkeletonText,
  StatTile,
  Tabs,
  TopBar,
  VisitScoreBadge,
  toast,
  type DataTableColumn,
  type DateRange,
  type FilterValues,
} from "@/components/ds";
import { ThemeToggle } from "@/components/theme/ThemeToggle";
import { formatDateIst, formatInr, formatInrCompact, formatNumber } from "@/lib/format";

type Officer = {
  id: string;
  name: string;
  cluster: string;
  visits: number;
  score: number;
  collections: number;
};
const officers: Officer[] = [
  {
    id: "o1",
    name: "Ramesh Reddy",
    cluster: "Kondapur",
    visits: 8,
    score: 88,
    collections: 12500000,
  },
  {
    id: "o2",
    name: "Anita Kulkarni",
    cluster: "Belagavi",
    visits: 6,
    score: 55,
    collections: 4230050,
  },
  { id: "o3", name: "Kiran Patil", cluster: "Latur", visits: 2, score: 21, collections: 0 },
];
const columns: DataTableColumn<Officer>[] = [
  { id: "name", header: "Officer", accessor: (r) => r.name, sortable: true },
  { id: "cluster", header: "Cluster", accessor: (r) => r.cluster, sortable: true },
  {
    id: "visits",
    header: "Verified visits/day",
    accessor: (r) => r.visits,
    sortable: true,
    numeric: true,
  },
  {
    id: "score",
    header: "Visit score",
    accessor: (r) => r.score,
    sortable: true,
    cell: (r) => <VisitScoreBadge score={r.score} />,
  },
  {
    id: "collections",
    header: "Collections",
    accessor: (r) => r.collections,
    sortable: true,
    numeric: true,
    cell: (r) => formatInr(r.collections),
  },
];

function Section({ name, children }: { name: string; children: React.ReactNode }) {
  return (
    <section className="mb-8 flex flex-col gap-3" data-component={name}>
      <h2 className="border-b border-border pb-1 text-heading">{name}</h2>
      {children}
    </section>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <span className="w-24 shrink-0 text-small text-text-muted">{label}</span>
      {children}
    </div>
  );
}

export function Gallery({ theme }: { theme: "light" | "dark" }) {
  const [otp, setOtp] = React.useState("12");
  const [search, setSearch] = React.useState("Ramesh");
  const [range, setRange] = React.useState<DateRange>({ start: "2026-09-01", end: "2026-09-17" });
  const [badRange, setBadRange] = React.useState<DateRange>({
    start: "2026-09-17",
    end: "2026-09-01",
  });
  const [filters, setFilters] = React.useState<FilterValues>({ crop: "cotton" });
  const [segment, setSegment] = React.useState<"day" | "week" | "month">("week");
  const [dialogOpen, setDialogOpen] = React.useState(false);
  const [collapsed, setCollapsed] = React.useState(false);

  return (
    <div className="flex flex-col">
      <div className="mb-6 flex items-center justify-between">
        <span className="text-title">{theme === "dark" ? "Dark" : "Light"}</span>
        <ThemeToggle value={theme} onChange={() => {}} />
      </div>

      <Section name="Typography">
        <p className="text-display">Display 28/36 · Crop doctor</p>
        <p className="text-title">Title 22/30 · Pay dues</p>
        <p className="text-heading">Heading 18/26 · Verified visits</p>
        <p className="text-body">Body 15/22 · Ramesh Reddy, Kondapur — cotton, chilli, paddy.</p>
        <p className="text-small">Small 13/18 · Last visit 17-09-2026</p>
        <p className="tnum text-body">Tabular figures: 1,25,000 · 12,34,567 · 0.05</p>
        <p lang="te" className="text-body">
          పంట వైద్యుడు · బకాయిలు చెల్లించండి
        </p>
        <p lang="kn" className="text-body">
          ಬೆಳೆ ವೈದ್ಯ · ಬಾಕಿ ಪಾವತಿಸಿ
        </p>
        <p lang="hi" className="text-body">
          फसल डॉक्टर · बकाया चुकाएँ
        </p>
        <p lang="mr" className="text-body">
          पीक डॉक्टर · थकबाकी भरा
        </p>
      </Section>

      <Section name="AppButton">
        <Row label="Primary">
          <AppButton>Save</AppButton>
          <AppButton size="L">Save (L)</AppButton>
          <AppButton icon={<Plus />}>Add farmer</AppButton>
          <AppButton loading>Saving</AppButton>
          <AppButton disabled>Disabled</AppButton>
        </Row>
        <Row label="Secondary">
          <AppButton variant="secondary">Export</AppButton>
          <AppButton variant="secondary" icon={<Download />}>
            Export CSV
          </AppButton>
          <AppButton variant="secondary" loading>
            Exporting
          </AppButton>
          <AppButton variant="secondary" disabled>
            Disabled
          </AppButton>
        </Row>
        <Row label="Tertiary">
          <AppButton variant="tertiary">Cancel</AppButton>
          <AppButton variant="tertiary" disabled>
            Disabled
          </AppButton>
        </Row>
        <Row label="Destructive">
          <AppButton variant="destructive">Delete</AppButton>
          <AppButton variant="destructive" loading>
            Deleting
          </AppButton>
          <AppButton variant="destructive" disabled>
            Disabled
          </AppButton>
        </Row>
      </Section>

      <Section name="AppTextField">
        <div className="grid gap-4 md:grid-cols-2">
          <AppTextField label="Farmer name" helper="As on Aadhaar" defaultValue="Ramesh Reddy" />
          <AppTextField
            label="Mobile number"
            phone
            helper="10-digit Indian mobile"
            defaultValue="9876543210"
          />
          <AppTextField label="Village" error="Village is required" defaultValue="" />
          <AppTextField label="Notes" optional disabled defaultValue="Disabled field" />
        </div>
      </Section>

      <Section name="OtpInput">
        <Row label="Default">
          <OtpInput value={otp} onChange={setOtp} resendAfterSeconds={20} />
        </Row>
        <Row label="Error">
          <OtpInput
            value="123456"
            onChange={() => {}}
            error="Code did not match"
            resendAfterSeconds={0}
          />
        </Row>
        <Row label="Disabled">
          <OtpInput value="12" onChange={() => {}} disabled />
        </Row>
      </Section>

      <Section name="KpiCard">
        <div className="grid gap-3 md:grid-cols-2">
          <KpiCard
            title="Revenue (MTD)"
            value={formatInrCompact(1245000000)}
            target={formatInrCompact(1500000000)}
            progress={0.83}
            trend="up"
            trendValue="+8.2%"
          />
          <KpiCard
            title="Credit overdue"
            value={formatInrCompact(320000000)}
            trend="up"
            trendValue="+3.1%"
            invertTrendColor
            onClick={() => toast.info("KPI clicked")}
          />
          <KpiCard
            title="Verified visits"
            value={formatNumber(1842)}
            target="2,000"
            progress={0.92}
            trend="flat"
          />
          <KpiCard title="Open flags" value="—" loading />
          <KpiCard title="Own-brand share" value="—" error="Could not load" />
        </div>
      </Section>

      <Section name="StatTile">
        <Row label="States">
          <StatTile value={formatNumber(24)} label="Stores" />
          <StatTile value="68%" label="Own-brand share" trend="up" trendValue="+4%" />
          <StatTile
            value={formatInr(4230050)}
            label="Overdue"
            trend="down"
            trendValue="-2%"
            invertTrendColor
          />
          <StatTile value="12" label="Flags" trend="flat" />
          <StatTile value="" label="" loading />
        </Row>
      </Section>

      <Section name="SeverityBadge">
        <Row label="Levels">
          <SeverityBadge severity="critical" />
          <SeverityBadge severity="high" />
          <SeverityBadge severity="medium" />
          <SeverityBadge severity="low" />
        </Row>
      </Section>

      <Section name="VisitScoreBadge">
        <Row label="Bands">
          <VisitScoreBadge score={92} />
          <VisitScoreBadge score={70} />
          <VisitScoreBadge score={55} />
          <VisitScoreBadge score={40} />
          <VisitScoreBadge score={18} />
          <VisitScoreBadge score={18} showLabel={false} size="sm" />
        </Row>
      </Section>

      <Section name="ConfidenceBand">
        <Row label="Levels">
          <ConfidenceBand level="high" />
          <ConfidenceBand level="medium" />
          <ConfidenceBand level="low" />
          <ConfidenceBand level="low" provisional />
        </Row>
      </Section>

      <Section name="OwnBrandBadge">
        <Row label="Variants">
          <OwnBrandBadge />
          <OwnBrandBadge brandName="Kisan Gold" />
          <OwnBrandBadge compact />
        </Row>
      </Section>

      <Section name="FlagCard">
        <div className="grid gap-3">
          <FlagCard
            id="f1"
            title="Visit outside geofence"
            severity="high"
            rule="VV-003"
            officerName="Ramesh Reddy"
            summary="Check-in 420 m from farm boundary; 3 photos, no farmer confirmation."
            raisedAt="2026-09-17T04:30:00Z"
            slaMinutesLeft={95}
            onOpen={() => {}}
            onAssign={() => {}}
          />
          <FlagCard
            id="f2"
            title="Duplicate farmer phone"
            severity="medium"
            rule="FA-013"
            officerName="Anita Kulkarni"
            raisedAt="2026-09-16T11:00:00Z"
            slaMinutesLeft={-30}
            onOpen={() => {}}
          />
          <FlagCard
            id="f3"
            title="Loading"
            severity="low"
            rule="—"
            raisedAt="2026-09-16T11:00:00Z"
            loading
          />
        </div>
      </Section>

      <Section name="DataTable">
        <DataTable
          columns={columns}
          rows={officers}
          rowKey={(r) => r.id}
          caption="Officer scorecard"
          onRowClick={(r) => toast.info(r.name)}
        />
        <DataTable columns={columns} rows={[]} rowKey={(r) => r.id} loading skeletonRows={2} />
        <DataTable
          columns={columns}
          rows={[]}
          rowKey={(r) => r.id}
          emptyTitle="No officers"
          emptyHelp="Try clearing filters."
        />
        <DataTable
          columns={columns}
          rows={[]}
          rowKey={(r) => r.id}
          error="HTTP 503 from /officers"
          onRetry={() => {}}
        />
      </Section>

      <Section name="FilterBar">
        <FilterBar
          value={filters}
          onChange={setFilters}
          options={{
            clusters: [
              { value: "tg", label: "Telangana" },
              { value: "ka", label: "Karnataka" },
              { value: "mh", label: "Maharashtra" },
            ],
            stores: [
              { value: "s1", label: "Kondapur" },
              { value: "s2", label: "Belagavi" },
            ],
            officers: [{ value: "o1", label: "Ramesh Reddy" }],
            crops: [
              { value: "cotton", label: "Cotton" },
              { value: "chilli", label: "Chilli" },
              { value: "paddy", label: "Paddy" },
            ],
          }}
          onExport={() => toast.success("Export started")}
        />
        <FilterBar value={{}} onChange={() => {}} options={{}} disabled />
      </Section>

      <Section name="DateRangePicker">
        <Row label="Default">
          <DateRangePicker value={range} onChange={setRange} />
        </Row>
        <Row label="Invalid">
          <DateRangePicker value={badRange} onChange={setBadRange} />
        </Row>
        <Row label="Disabled">
          <DateRangePicker value={range} onChange={() => {}} disabled />
        </Row>
      </Section>

      <Section name="SideNav">
        <div className="flex h-72 overflow-hidden rounded-card border border-border">
          <SideNav
            collapsed={collapsed}
            onCollapsedChange={setCollapsed}
            activePath="/farmers"
            header={
              <span className="flex items-center gap-2 text-heading text-primary">
                <Leaf className="size-6" aria-hidden="true" />
                {collapsed ? null : "FarmerApp"}
              </span>
            }
            items={[
              { href: "#home", label: "Home", icon: <Home /> },
              { href: "#field", label: "Field team", icon: <Users /> },
              { href: "/farmers", label: "Farmers", icon: <Users /> },
              { href: "#stores", label: "Stores", icon: <Store /> },
              { href: "#flags", label: "Flags", icon: <Flag />, badge: 4 },
            ]}
          />
          <div className="flex-1 bg-background p-4 text-small text-text-muted">Content area</div>
        </div>
      </Section>

      <Section name="TopBar">
        <div className="overflow-hidden rounded-card border border-border">
          <TopBar
            tenantName="Kisan Agro Centre"
            onTenantClick={() => {}}
            search={search}
            onSearchChange={setSearch}
            dateRange={range}
            onDateRangeChange={setRange}
            unreadNotifications={7}
            user={{ name: "Suresh Patil", role: "Owner" }}
          />
        </div>
      </Section>

      <Section name="EmptyState">
        <EmptyState />
        <EmptyState
          title="No farmers yet"
          help="Add your first farmer from the field app or import a CSV."
          action={<AppButton icon={<Plus />}>Add farmer</AppButton>}
        />
      </Section>

      <Section name="ErrorState">
        <ErrorState onRetry={() => {}} />
        <ErrorState
          title="Could not load flags"
          detail="HTTP 503 — upstream timeout"
          onRetry={() => {}}
          retrying
        />
      </Section>

      <Section name="Skeleton">
        <Row label="Blocks">
          <Skeleton className="h-10 w-40" />
          <Skeleton className="size-10 rounded-pill" />
        </Row>
        <SkeletonText lines={3} className="max-w-md" />
      </Section>

      <Section name="Toasts">
        <Row label="Trigger">
          <AppButton variant="secondary" onClick={() => toast.success("Saved", "Store updated")}>
            Success
          </AppButton>
          <AppButton variant="secondary" onClick={() => toast.error("Failed", "Could not save")}>
            Error
          </AppButton>
          <AppButton variant="secondary" onClick={() => toast.warning("Check", "Verify evidence")}>
            Warning
          </AppButton>
          <AppButton variant="secondary" onClick={() => toast.info("Info")}>
            Info
          </AppButton>
        </Row>
      </Section>

      <Section name="Dialog">
        <Row label="Trigger">
          <AppButton variant="destructive" onClick={() => setDialogOpen(true)}>
            Delete store
          </AppButton>
        </Row>
        <Dialog
          open={dialogOpen}
          onOpenChange={setDialogOpen}
          title="Delete store?"
          description="This removes Kondapur store and its day-close history. This cannot be undone."
          confirmLabel="Delete"
          destructive
          onConfirm={() => setDialogOpen(false)}
        />
      </Section>

      <Section name="Tabs">
        <Tabs
          label="Farmer sections"
          items={[
            {
              value: "overview",
              label: "Overview",
              content: <p className="text-body text-text-secondary">Key facts, crops and map.</p>,
            },
            {
              value: "visits",
              label: "Visits",
              count: 12,
              content: <p className="text-body text-text-secondary">Visit history.</p>,
            },
            {
              value: "khata",
              label: "Khata",
              content: <p className="text-body text-text-secondary">Ledger.</p>,
            },
            { value: "usage", label: "App usage", disabled: true },
          ]}
        />
      </Section>

      <Section name="SegmentedControl">
        <Row label="Default">
          <SegmentedControl
            label="Period"
            value={segment}
            onChange={setSegment}
            options={[
              { value: "day", label: "Day" },
              { value: "week", label: "Week" },
              { value: "month", label: "Month" },
            ]}
          />
          <SegmentedControl
            label="Period small"
            size="sm"
            value={segment}
            onChange={setSegment}
            options={[
              { value: "day", label: "Day" },
              { value: "week", label: "Week" },
              { value: "month", label: "Month", disabled: true },
            ]}
          />
          <SegmentedControl
            label="Disabled"
            disabled
            value="day"
            onChange={() => {}}
            options={[
              { value: "day", label: "Day" },
              { value: "week", label: "Week" },
            ]}
          />
        </Row>
      </Section>

      <Section name="SearchBar">
        <Row label="Default">
          <SearchBar value={search} onChange={setSearch} className="w-72" />
        </Row>
        <Row label="Loading">
          <SearchBar value="98765" onChange={() => {}} loading className="w-72" />
        </Row>
        <Row label="Disabled">
          <SearchBar value="" onChange={() => {}} disabled className="w-72" />
        </Row>
      </Section>

      <Section name="Formatting">
        <p className="tnum text-body">
          {formatInr(12500000)} · {formatInr(12500050)} · {formatInrCompact(1245000000)} ·{" "}
          {formatNumber(1234567)} · {formatDateIst("2026-09-17T04:30:00Z")}
        </p>
      </Section>
    </div>
  );
}
