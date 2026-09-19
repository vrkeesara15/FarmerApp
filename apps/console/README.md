# FarmerApp console

Next.js 15 (App Router) · TypeScript strict (`noUncheckedIndexedAccess`) · Tailwind CSS 3 · shadcn/ui · TanStack Query.

## Scripts

| Script                    | What it does                                                                                                                                       |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `npm run dev`             | Dev server (uses the in-app mock API at `/api/mock` unless `NEXT_PUBLIC_API_URL` is set)                                                           |
| `npm run build` / `start` | Production build (runs `prebuild` = `tokens`) / serve                                                                                              |
| `npm run lint`            | ESLint (next/core-web-vitals + typescript) **and** `scripts/lint-strings.mjs` (no hard-coded UI strings)                                           |
| `npm run typecheck`       | `tsc --noEmit`                                                                                                                                     |
| `npm run test`            | Vitest (jsdom + Testing Library)                                                                                                                   |
| `npm run test:e2e`        | Playwright smoke against `next start` + mock API. Build first (`npm run build`) or set `PW_BUILD=1`. Needs `npx playwright install chromium` once. |
| `npm run check`           | `lint && typecheck && test && build` — what the root `Makefile` and `ci-console.yml` run                                                           |
| `npm run size`            | Prints `.next/static` bundle sizes; fails if `SIZE_LIMIT_KB` is set and exceeded                                                                   |
| `npm run tokens`          | Regenerates `app/tokens.css` from `../../design/tokens.json`                                                                                       |

## Design system

- Tokens: `design/tokens.json` → `scripts/tokens-to-css.mjs` → `app/tokens.css` (`:root, [data-theme="light"]` and `[data-theme="dark"]`). `tailwind.config.ts` maps the theme onto those variables; never hard-code hex in components.
- Components: `components/ds/<Name>.tsx`, named exactly as SPEC 13.1; docs in `design/components/<Name>.md`; gallery at `/design` (both themes side by side).
- Theme: `data-theme` on `<html>`, persisted in localStorage by `components/theme/ThemeToggle.tsx`.
- Fonts: Noto Sans + Telugu/Kannada/Devanagari via `next/font/google` (`lib/fonts.ts`); `:lang(te|kn|hi|mr)` picks the script font and adds ~15% line-height. Numbers: `.tnum` / `data-numeric`.
- Formatting: `lib/format.ts` — `formatInr(paise)` (Indian grouping), `formatDateIst` (DD-MM-YYYY).

## i18n

All UI strings live in `messages/en.json` (source of truth and the type). `te/kn/hi/mr.json` carry every key (`lib/i18n.test.ts` fails otherwise, FA-004); `t()` from `lib/i18n.ts` still falls back to English per key.

- Server components and `metadata` call `t(key)` (English).
- Client components call `const t = useT()` from `lib/i18n-client.ts`; it re-renders on `setLocale()` so the language switches without a reload. `useLocale()` gives the current code.
- The choice lives in `localStorage` (`farmerapp.console.locale`, best effort) and is stamped on `<html lang>` before hydration by `localeInitScript`; `globals.css` maps `:lang(te|kn|hi|mr)` to the Noto script fonts and the +15% line height. Users switch from the TopBar profile menu (five languages in their own script); there is no separate language screen (SPEC 13.4).

`npm run lint:strings` fails on raw JSX text and on string literals in `placeholder`, `title`, `aria-label`, `alt`, `label`. Allowlist by:

1. adding an `i18n-ignore` comment on the same or previous line (JSX comment or `//`), or
2. adding a path prefix to `ALLOW_PATHS` in `scripts/lint-strings.mjs` (currently `app/design/`, `components/ui/`, `e2e/`; `*.test.tsx` are skipped).

## API

`lib/api.ts` wraps `fetch`, base URL `NEXT_PUBLIC_API_URL` (default `/api/mock`), JSON in/out, RFC 9457 `problem+json` → `ApiError { status, problem }` with the stable `problem.code` (`otp_locked`, `otp_rate_limited`, ...). Paths carry the API version (`v1/auth/otp/send`).

Auth (FA-001): `auth.sendOtp` / `auth.verifyOtp` call the real `/v1/auth/*` endpoints; the access token (15 min) is kept in memory only and the refresh token goes to an httpOnly, SameSite=Strict cookie via the Next route handlers `app/api/session` (POST store / DELETE revoke+clear) and `app/api/session/refresh` (rotate against `/v1/auth/refresh`; server-side base URL `API_URL` or `NEXT_PUBLIC_API_URL`). The mock (`app/api/mock/[...path]/route.ts`) mirrors the same shapes: any `+91` mobile, OTP `123456`, lockout after 5 wrong codes, 3 resends per 15 min, `+919999999999` = unknown number.

## Session and data layer (WC-005)

- `lib/session-context.tsx` — `SessionProvider` (mounted by `ConsoleShell`) restores the in-memory access token after a page load via `session.refresh()` (the httpOnly cookie route; concurrent refreshes share one request so a rotated token is never replayed) and exposes `useSession()` → `{ status, user, role }`. The TopBar shows the signed-in name and role; sign-out revokes and returns to `/login`.
- `authedFetch` (`lib/api.ts`) — bearer token from the session; a 401 triggers one refresh + retry.
- `lib/catalog.ts` (typed `/v1/catalog/*` calls and role lists), `lib/hooks/catalog.ts` (TanStack Query hooks; queries wait for `status === "authenticated"`; every write invalidates the catalogue cache), `lib/catalog-schemas.ts` (zod schemas for react-hook-form, mirroring the API rules), `lib/problem-messages.ts` (problem `code` → `problems.*` message key).
- Screens: C50 `/products`, C51 `/products/label-claims` (Approve only for the agronomist — SPEC 14.6 human gate; "Preview recommendation" calls `GET /v1/catalog/recommendable`), C52 `/products/prices`. Specs in `design/screens/C50.md`–`C52.md`.

## Mock API roles and catalogue

Any `+91` mobile signs in to the mock as the **owner** (code `123456`). Other roles use fixed numbers (`MOCK_ROLE_BY_PHONE` in `app/api/mock/[...path]/route.ts`): `9000000002` director, `…03` cluster head, `…04` store manager, `…05` auditor, `…06` accountant, `…07` field officer, **`9000000008` agronomist**, `…09` tenant admin. The role travels in the mock tokens (`mock-access-<role>-<ts>`), so a refresh keeps it.

`/v1/catalog/*` is served by `lib/mock/catalog.ts`: an in-memory catalogue (4 products incl. one own brand and one inactive, 5 SKUs with barcodes, the 6 pilot crops, 6 pests / diseases incl. polyphagous aphids, 3 stores, one claim per status, default + store prices) with the API's roles, validation and problem codes. It lives as long as the `next start` process; `resetMockState()` (tests) restores the seed. Vitest routes `fetch` to the same handler through `test/mock-fetch.ts`.

`/v1/analytics/*` (M4) is served by `lib/mock/analytics.ts`: 24 stores in Telangana, Karnataka and Maharashtra (clusters `cluster-tg` / `cluster-ka` / `cluster-mh`), 30 officers, 72 farmers; every figure is a deterministic function of (entity, IST day), so any date range works. Same shapes, roles and AN-011 problems as the API (`invalid_date_range`, `invalid_filter_combination`, `not_found`); the mock store manager runs `store-wgl` (no km, 403 on the day replay), the cluster head `cluster-tg`, the field officer is `off-wgl-1`. Replays: every weekday has a duty 08:30–17:30 IST with four visits (verified, partial, unverified, verified), a stop and two gaps (one without a reason); Sundays and future days are empty.

## Analytics screens (M4)

C10 `/home`, C20 `/field-team`, C21 `/field-team/{id}`, C22 `/field-team/{id}/replay?date=`, C30 `/farmers`, C31 `/farmers/{id}`, C40 `/stores`, C41 `/stores/{id}` (specs in `design/screens/`). Filters (AN-011) live in the URL through `useAnalyticsFilters()` (`lib/hooks/use-analytics-filters.ts`, pure mapping in `lib/analytics-filters.ts`): `from`, `to`, `cluster`, `store`, `officer`, `crop`; default the last 30 days (IST), written with `router.push` so reload and back / forward keep them. Charts use Recharts, maps Leaflet with OpenStreetMap raster tiles (no key); both are lazy chunks (`next/dynamic`, `ssr: false`) under `components/analytics/{charts,maps}`, coloured from the design tokens (`components/analytics/charts/palette.ts`). Exports are client-side CSV of the table view (`lib/csv.ts`); scheduled exports are WC-013. Role-based navigation lives in `lib/nav.ts`.
