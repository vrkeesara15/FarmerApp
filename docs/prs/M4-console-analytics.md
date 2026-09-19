# M4 console analytics — WC-001 .. WC-004, AN-001 .. AN-003, AN-011 (console half)

Branch `feat/M4-console-analytics` (from `main` 1a4c118). Console screens over the M4 analytics
read API (docs/prs/M4-analytics-api.md): C10 owner home, C20 field team, C21 officer profile,
C22 day replay, C30 farmers directory, C31 farmer 360, C40 stores, C41 store detail. Only
`apps/console`, `design/screens/C10-C41.md` and docs change. No API change.

## What is new

| Area | Files |
|---|---|
| AN-011 filters in the URL | `lib/analytics-filters.ts` (pure parse / serialize / change / reconcile), `lib/hooks/use-analytics-filters.ts` (`useAnalyticsFilters()`, `useSearchParam`, `useSetSearchParams`), `components/analytics/AnalyticsFilterBar.tsx` |
| API layer | `lib/analytics.ts` (types from the openapi schemas, `analytics.*` client), `lib/hooks/analytics.ts` (TanStack hooks, `keepPreviousData`, `useFilterOptions`, `pnlWindow`) |
| Charts | Recharts 3.10.1: `components/analytics/charts/{LineTrend,BarCompare,ShareDonut}.tsx` lazy via `charts/index.tsx` (`next/dynamic`, `ssr: false`); SVG `Sparkline`; token palette `charts/palette.ts` |
| Maps | Leaflet 1.9.4 + OpenStreetMap raster tiles (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`, attribution "© OpenStreetMap contributors", no key): `components/analytics/maps/{StoreMap,ReplayMap,FarmsMap}.tsx`, lazy via `maps/index.tsx` (`ssr: false`) — same library, version and tiles as the inbox branch's `EvidenceMap` |
| Shared UI | `components/analytics/{Page,ProblemState,InfoTip,KpiTile,Definitions,ProofChecklist}.tsx`; `KpiCard` gains an additive `titleAddon` slot |
| Formatting / export | `lib/analytics-format.ts` (IST days DD-MM-YYYY, HH:mm IST, ratios, durations), `lib/kpi.ts` (KPI card maths), `lib/csv.ts` (client CSV, BOM, formula neutralisation) |
| Replay maths | `lib/replay.ts` (slider ↔ time, marker position, highlighted timeline item, gap segments) |
| Role-based nav | `lib/nav.ts` (`ROUTE_ROLES`, `canSeeReplay`, `filterVisibility`); `ConsoleShell` filters its items (additive) |
| Screens | `app/(console)/home`, `field-team` (+ `[id]`, `[id]/replay`), `farmers` (+ `[id]`), `stores` (+ `[id]`) |
| Mock API | `lib/mock/analytics.ts` wired into `app/api/mock/[...path]/route.ts` (additive) |
| Strings | ~420 keys in `messages/en.json` with Telugu, Kannada, Hindi and Marathi translations |

## Behaviour

* **Filters (AN-011, acceptance "filters persist in URL")**: `from`, `to`, `cluster`, `store`,
  `officer`, `crop` in the query string; default the 30 days ending today (IST) and not written
  to the URL; changes use `router.push` (back / forward step through them), corrections use
  `replace`. Malformed dates are dropped, a reversed range swapped, a range over 366 days cut
  (the API would answer 422) — with a notice. Choosing a cluster clears the store and officer,
  choosing a store clears the officer; once the option lists load, a store outside the cluster
  or an officer outside the store is dropped. API 422 (`invalid_filter_combination`,
  `invalid_date_range`) and 404 show explanatory states with "Reset filters". Links between
  dashboards carry the filters. Filters a role cannot change are hidden (cluster head: cluster;
  store manager: cluster, store; field officer: cluster, store, officer).
* **Every data view** has the FilterBar, an export button (client-side CSV of the table view;
  money in rupees, masked phones only in the directory export) and loading / empty / error
  states.
* **C10 performance**: one owner-home request in parallel with the option lists; KPIs render as
  soon as it lands; Recharts / Leaflet are separate chunks behind skeletons. Build: /home first
  load 180 kB; client chunks 2,296 KB total (CI budget 3,072 KB).
* **Charts**: lines for trends, bars for comparisons, maps for geography; the only pie-type
  chart is the own-brand donut on C10. No dual axes (revenue and own-brand share are two
  charts). Categorical order Leaf / info blue / warning amber (validated for CVD separation and
  contrast in light and dark; the dark tokens sit slightly above the lightness band — accepted
  as the approved dark theme), own brand always Turmeric, comparisons muted, status colours
  only for states and always with text.
* **Permissions (SPEC 2.6)**: SideNav hides `/home` for accountants / field officers /
  agronomists, `/stores` for field officers / agronomists, `/farmers` and `/field-team` for
  accountants / agronomists. Direct URLs show the no-access state. Store managers: no km
  column, no replay picker or links on C21, and C22 refuses without calling the API (a 403
  from the API gets the same explanation: "Location tracks are never shown to store managers or
  to other officers.").
* **Replay**: track split at gaps; each gap drawn dashed between the points around it with its
  reason or "No reason given" (VV-008 pending); stops; pins by status; playback slider (0-1000
  over the day, play / pause) moves the marker (interpolated, held and faded during a gap) and
  highlights the timeline item at or before that time; timeline clicks jump the slider and open
  the visit with its ProofChecklist.
* **Store P&L**: C41 asks for the 12 months ending at the filter's end day in a second request
  (parallel) and shows gross sales → contribution with partial months marked and the note that
  operating expenses are not included.

## Tests

* Vitest (42 files, 225 tests; new: 7 files, 57 tests):
  `lib/analytics-filters.test.ts` (defaults, IST today, URL round trip, other params kept,
  malformed / reversed / long ranges, bad ids, hierarchy clearing, reconcile),
  `lib/hooks/use-analytics-filters.test.tsx` (in-memory router: push, reload, back / forward,
  replace, reset, `useSearchParam`), `lib/kpi.test.tsx` (value / delta / trend formatting and
  the rendered tile with its tooltip), `lib/csv.test.ts`, `lib/replay.test.ts` (marker
  position and highlighted timeline item for given slider values), `lib/nav.test.tsx`
  (role-based nav), `lib/mock/analytics.test.ts` (mock contract: shapes, AN-011 problems,
  roles, replay, directory paging, P&L identities).
* Playwright `e2e/analytics.spec.ts` (6): owner home loads every section; a filter change updates
  the URL and survives reload and back; field team → officer → replay shows track, visits and a
  gap (plus slider / timeline / ProofChecklist); farmers search → 360 tabs; store detail shows
  the P&L by month; a store manager cannot open the replay. `e2e/smoke.spec.ts`: the four
  dashboards now ask to sign in when signed out (they were placeholders).

## Assumptions / follow-ups

* Clusters have no names in the P0 API; the cluster filter labels a cluster by its first store's
  district ("Warangal cluster (8 stores)").
* The 360 payload has no visit photo counts or khata entries: the visits tab shows a photo
  column only when the API adds `photos`; the khata tab shows balance, buckets and limits with a
  note that entry lines are on the store khata screen. Diagnoses with photos wait for M6.
* Crop health alerts stay an empty state until AN-006.
* `npm audit --audit-level=high --omit=dev` still reports the pre-existing `next` → `postcss`
  advisory (unchanged by this branch; Recharts and Leaflet add none).
* Shared files touched additively: `ConsoleShell.tsx` (nav filter), `messages/*.json`, the mock
  router, `components/ds/KpiCard.tsx` (`titleAddon`), `e2e/smoke.spec.ts`, `README.md`,
  `package.json` / lock (recharts, leaflet, @types/leaflet).
