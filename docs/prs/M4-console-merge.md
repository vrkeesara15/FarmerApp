# M4 console merge — analytics + inbox / admin on main

Merges `feat/M4-console-analytics` (C10-C41, docs/prs/M4-console-analytics.md) and
`feat/M4-console-inbox-admin` (C70, C71, C101-C103, docs/prs/M4-console-inbox-admin.md) into
`main` (`merge(M4): …` commits), then closes the cross-branch gaps both agents recorded.

## Merge resolution

| File | Resolution |
|---|---|
| `messages/{en,te,kn,hi,mr}.json` | Three-way union of keys (no value conflicts; 1,100 keys in every locale, no missing / extra keys) |
| `app/(console)/ConsoleShell.tsx` | Nav entries from both, SPEC 13.4 order (home, field team, farmers, stores, products, label claims, prices, agronomist, flags, users, settings, audit, design). The inbox branch's `NAV_ROLES` moved into `lib/nav.ts` `ROUTE_ROLES`, so one map gates the nav and the analytics page guard |
| `app/api/mock/[...path]/route.ts` | Catalog → analytics → clusters → flags → admin, one `toResponse`; `resetMockState` resets all |
| `e2e/smoke.spec.ts` | `/agronomist` stays a placeholder; the eight data screens ask to sign in when signed out |
| `package.json` / lock | One `leaflet@1.9.4` and `@types/leaflet@1.9.22`, `recharts@3.10.1`; lock regenerated with `npm install` |
| Maps | One setup: `lib/map-config.ts` (`MAP_TILE_URL`, `NEXT_PUBLIC_MAP_TILE_URL` override, `MAP_MAX_ZOOM`) used by `components/analytics/maps/base.ts` and `components/flags/EvidenceMapLeaflet.tsx`; the EvidenceMap attribution now comes from the i18n key `map.attribution` instead of a hard-coded string |
| `docs/progress.md` | Newest status per row (M4-KICKOFF from main, WC-001-004 / AN-* from analytics, WC-010-012 / WC-103 from inbox-admin) |

`lib/nav.test.tsx` was updated for the combined gating (flags, users, settings, audit are now
role-filtered in the same map).

## Cross-links (task 2)

* `RECORD_ROUTES` (`farmer` → `/farmers/{id}`, `user` → `/field-team/{id}`) already match the
  analytics routes; no change. Evidence record types emitted by the P0 rules are farmer, user,
  farm, visit, visit_photo, visit_confirmation, duty_session, location_point; only farmer and
  user have console screens.
* C10's open high-severity flags link to `/flags/{id}`. The two mocks were disjoint (home used
  `flag-101…`, the inbox `f1a90000-…`), so the link 404'd in the mock. The home mock now reads
  the inbox mock's open high / critical flags (`mockOpenHighSeverityFlags()`), as the API reads
  one `flag` table, and the inbox mock's evidence records point at analytics mock farmers /
  officers (`MOCK_EVIDENCE_FARMER_IDS`, `MOCK_EVIDENCE_OFFICER_IDS`). Names in the evidence
  summaries stay as the rule fixtures wrote them (mock only).
* Playwright `e2e/cross-links.spec.ts`: owner home → "Farm boundary overlaps a neighbour" →
  evidence record "Yadagiri" → `/farmers/farmer-010` (header + farms map).

## Gaps closed (task 4)

a. **`GET /v1/clusters`** (`apps/api/farmerapp/tenants/clusters_router.py`, operation
   `listClusters`): `{items: [{id, name, district, state, store_ids}]}` ordered by name. Every
   staff role (farmer 403); rows per SPEC 2.6 — owner / director / tenant_admin / auditor /
   accountant: all clusters and stores; cluster_head: own cluster; store_manager /
   field_officer: the cluster of their store listing only that store; agronomist: empty.
   Tests `tests/authz/test_clusters.py` (every role, tenant isolation) plus the generated
   authz matrix. Console: `lib/clusters.ts`, `lib/hooks/clusters.ts`; the AN-011 cluster filter
   reads names (e.g. "North Telangana cluster (n stores)") instead of "first store's district", and
   the C101 create / edit cluster pickers and the assignment labels show names (ids outside the
   caller's scope keep the short "Cluster …c001" label).
b. **Device status in `GET /v1/users`**: rows are `UserListItem` = `UserOut` + `device_status`
   (`pending` > `active` > `lost` > `revoked`, else `none` — the console's former
   `deviceSummary` order) + `latest_device` (`device_id, platform, model, status, last_seen`
   of the most recently seen device). One extra query per page (`device.user_id IN (…)`).
   `GET /v1/users/{id}` is unchanged. Test `tests/admin/test_users_list_devices.py`. C101's
   table no longer fetches devices per row.
c. **TopBar date range bound to the filters**: on `/home`, `/field-team`, `/farmers`, `/stores`
   (and their sub-pages; `isAnalyticsRoute` in `lib/nav.ts`) the TopBar reads and writes `from`
   / `to` through `useAnalyticsFilters()` (a change is a history entry, other params kept);
   elsewhere it keeps the shell's own range. `BoundTopBar` sits in a `<Suspense>` with the
   plain TopBar as fallback (Next's `useSearchParams` rule). Playwright checks both directions,
   reload and back.

`make openapi` regenerated `apps/api/openapi.yaml` (new path and schemas `ClusterOut`,
`ClusterList`, `DeviceBrief`, `UserListItem`, `PageOut_UserListItem_`); running it again leaves the
file unchanged.

## npm audit (task 3) — not cleared, recorded

`npm audit --audit-level=high --omit=dev` in `apps/console` still fails:

* **Advisories**: `postcss <= 8.5.22` — GHSA-6g55-p6wh-862q and GHSA-r28c-9q8g-f849 (high:
  arbitrary `.map` file read via an attacker-controlled `sourceMappingURL` in processed CSS),
  GHSA-fxqj-rqcc-2cmp and GHSA-qx2v-qp2m-jg93 (moderate: incomplete fix of the former; XSS via
  unescaped `</style>` in stringified CSS). Reached only through `next`, which pins its own
  `postcss@8.4.31` (our direct `postcss` is 8.5.28).
* **Why no upgrade**: `next@15.5.25` (2026-08-31) is already the newest 15.x release and still
  depends on `postcss@8.4.31`; the first release that clears it is `next@16.3.5` (depends on
  `postcss@8.5.23`), a major upgrade, so it was not done. `eslint-config-next` stays at 15.5.25.
* **Not exploitable in this deployment**: Next's bundled PostCSS runs only in `next build`, on
  our own stylesheets (`app/globals.css`, Tailwind output, `leaflet/dist/leaflet.css`) — all
  first-party or pinned dependencies committed to the repo. The console never processes
  user-supplied CSS, at build time or at run time (`next start` does not invoke PostCSS per
  request), so neither the source-map file read nor the stringify XSS has an attacker-controlled
  input.
* **CI**: the `npm audit` step in `.github/workflows/ci-console.yml` is left unchanged (it will
  keep failing until the upgrade).
* **Follow-up (due 2026-10-17)**: ADR + branch for Next 16 (`next` / `eslint-config-next`
  16.3.x; check the App Router, `next/dynamic` `ssr: false` and `useSearchParams` Suspense rules,
  `next lint` removal, React 19.2 peer); or, if a 15.5.x backport bumps PostCSS first, take it.
  An npm `overrides` pin of `next>postcss` was not applied: it forces an untested PostCSS into
  Next's build pipeline and should be decided together with that ADR.

## Verification

* `SKIP_AUDIT=1 make check` green on every surface: API 2,783 passed / 1 skipped, coverage
  97.16 %, ruff, mypy strict, 11 rules valid, openapi up to date, bandit; console lint + string
  lint + typecheck + vitest 48 files / 275 tests + build; mobile format, analyze, string lint and
  flutter tests (13 + 541 + 190 + 9 = 753); infra terraform fmt + validate (bootstrap, dev, stg,
  prd; tflint / checkov not installed locally, skipped as before).
* `cd apps/console && npm run test:e2e`: 24 passed (22 from the two branches, updated for the shared
  mock and cluster names, + 2 in `e2e/cross-links.spec.ts`).
* `make openapi` run again → `openapi.yaml` unchanged.
* `npm audit --audit-level=high --omit=dev`: still exits 1 (postcss via next, see above).

## WC-001 performance test under coverage

`SKIP_AUDIT=1 make check` failed twice on `tests/analytics/test_performance.py` (owner home 30 d:
3.01 s and 3.29 s against the 3 s budget; 60 d ~2.06 s). The endpoint is untouched by this merge
(no API analytics change); the test passes alone without coverage (~1.2-1.6 s) and sits at
2.93 s alone with coverage, so the pytest-cov line tracer was being timed. The timed requests
now run with the tracer paused (`coverage.Coverage.current().stop()` / `start()`); the budget
stays 3 s and the owner-home code keeps its coverage from the other analytics tests.

## Left as is

* Evidence records of types farm / visit / visit_photo / duty_session / location_point have no
  console screen yet, so they are listed without a link (as before).
* `deviceSummary()` in `lib/admin.ts` stays (tested, mirrors the API's order); the table uses
  the API's `device_status`.
