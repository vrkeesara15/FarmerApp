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

All UI strings live in `messages/en.json` (source of truth and the type). `te/kn/hi/mr.json` may be partial; `t()` from `lib/i18n.ts` falls back to English per key.

`npm run lint:strings` fails on raw JSX text and on string literals in `placeholder`, `title`, `aria-label`, `alt`, `label`. Allowlist by:

1. adding an `i18n-ignore` comment on the same or previous line (JSX comment or `//`), or
2. adding a path prefix to `ALLOW_PATHS` in `scripts/lint-strings.mjs` (currently `app/design/`, `components/ui/`, `e2e/`; `*.test.tsx` are skipped).

## API

`lib/api.ts` wraps `fetch`, base URL `NEXT_PUBLIC_API_URL` (default `/api/mock`), JSON in/out, RFC 9457 `problem+json` → `ApiError { status, problem }`. The mock (`app/api/mock/[...path]/route.ts`) accepts any `+91` mobile and OTP `123456`.
