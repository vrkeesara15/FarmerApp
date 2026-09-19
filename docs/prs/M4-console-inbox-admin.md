# M4 console — validation inbox, flag detail, users and devices, settings, audit log

Branch `feat/M4-console-inbox-admin` (from `main` at `1a4c118`). Console half only; the API halves
landed in docs/prs/M4-rules-engine.md and docs/prs/M4-admin-api.md.

## Requirement IDs

- **WC-010** Validation inbox — done (both halves). C70 `/flags`, C71 `/flags/[id]`. Acceptance
  "each flag has an owner and an SLA": every FlagCard shows the owner and a live SLA countdown
  (e2e counts both against the cards).
- **WC-011** Users, roles, device binding, forced logout — done. C101 `/admin/users`,
  `/admin/users/[id]`.
- **WC-012** Settings — done. C102 `/settings` with the branding preview of both apps; the
  "changes audited" acceptance is shown by the post-save link into C103.
- **WC-103** Audit log viewer — done. C103 `/admin/audit`.
- Also: SEC-028 step-up in the console (reusable `useStepUp()`), VA-002 "evidence renders in
  WC-010", VA-005 console half (officers see their own flags and add explanations; marked in the
  thread). VA-004 stays P1: the summary box is present with a "not available yet" state.

## What changed (all in `apps/console`)

**Step-up (SEC-028)** — `lib/step-up.ts` holds the 5-minute token in module memory only (never
web storage, cookies or the query cache), `runWithStepUp(call, authenticate)` retries once after
a 401 `step_up_required`; `components/admin/StepUp.tsx` provides `StepUpProvider` + `useStepUp()`
(dialog: `POST /v1/auth/step-up/send`, OTP boxes, `POST /v1/auth/step-up`, attempts left,
cancel -> `StepUpCancelledError`). A 403 is never turned into a code prompt (role check first).

**Flags** — `lib/flags.ts` (types, SPEC 6.1 `TRANSITIONS`, `availableActions` = local diagram ∩
server `allowed_transitions`, reviewer roles only; `noteRequired`; `slaState` / countdown;
`evidenceGeometry`; `RECORD_ROUTES`), `lib/hooks/flags.ts`, `components/flags/FlagInbox.tsx`,
`FlagDetailView.tsx`, `SlaTimer.tsx`, `FlagStatusBadge.tsx`, `EvidenceMap.tsx` +
`EvidenceMapLeaflet.tsx`.

**Map approach** — Leaflet 1.9.4 (`leaflet`, `@types/leaflet` added, exact versions) with
OpenStreetMap raster tiles (`NEXT_PUBLIC_MAP_TILE_URL` overrides the tile URL), loaded with
`next/dynamic` client-only so it is not in the shared bundle (`/flags/[id]` first load 226 kB).
Points are vector circle markers (no marker image assets). Built as our own small component so
the flag screens do not depend on the analytics branch; if that branch picked MapLibre, one of the
two should be retired at merge.

**Admin** — `lib/admin.ts` (types, role lists, `auditDiff`, `auditQuery`, `deviceSummary`,
`patchNeedsStepUp`, calls incl. a CSV fetch that does not refresh the session on
`step_up_required`), `lib/settings-form.ts` (form model, unit conversion, validation mirroring
`TenantSettings`, changed-keys patch, 422 location -> field), `lib/hooks/admin.ts`,
`components/admin/{UsersView,UserDetailView,SettingsView,BrandingPreview,AuditView,AuditDiff,AdminSubNav,badges,common}.tsx`.
Routes `app/(console)/flags/[id]`, `app/(console)/admin/{users,users/[id],audit}`, `/admin` ->
`/admin/users`; `/flags` and `/settings` replace their placeholders.

**Shared files (additive only)**
- `app/(console)/ConsoleShell.tsx`: nav entries "Users and roles" and "Audit log"; my four entries
  are filtered by role (SPEC 2.6; everything else unchanged, all entries shown while signed out).
- `components/ds/FlagCard.tsx`: optional `ownerName`, `sla`, `badges` props.
- `components/ds/DataTable.tsx`: optional `expandedKeys` + `renderExpanded` (full-width detail row).
- `app/api/mock/[...path]/route.ts`: routes `/v1/flags*` to `lib/mock/flags.ts` and
  `/v1/auth/step-up*`, `/v1/users*`, `/v1/settings*`, `/v1/audit-logs*` to `lib/mock/admin.ts`;
  `resetMockState` resets both.
- `lib/problem-messages.ts`: codes `step_up_required`, `otp_*`, `invalid_transition`,
  `flag_resolved`, `assignee_invalid`, `phone_taken`, `invalid_assignment`, `role_not_grantable`,
  `cannot_modify_self`, `invalid_settings`.
- `messages/*.json`: new `admin`, `stepUp`, `flagDetail`, `users`, `devices`, `audit` namespaces,
  additions under `nav`, `flagCard`, `flags`, `settings`, `problems`; real te / kn / hi / mr.
- `e2e/smoke.spec.ts`: `/flags` and `/settings` are data screens now, so signed out they show the
  sign-in state (with `/admin/users` and `/admin/audit`) instead of the placeholder EmptyState.

**Mock API** — shapes from `openapi.yaml`: `FlagPage` with counts over the filtered set, offset
cursors, `FlagDetailOut` (evidence with GeoJSON points / polygons, inline-SVG "signed" photos,
metrics, events, comments with `is_subject_explanation`, `allowed_transitions`), transitions with
409 `invalid_transition` / `note_required` and escalation to the auditor; users / devices with the
guard rails (`role_not_grantable`, `cannot_modify_self`, `phone_taken`, `invalid_assignment`);
settings validation (422 `invalid_settings`) and `tenant_settings.update` audit rows; audit list
filters (action prefix, `q`), CSV export; step-up send / verify (code 123456, 5 wrong -> 423) and
401 `step_up_required` on every `x-step-up` operation. Every mock write appends an audit row.

## Decisions and assumptions

- No cluster list endpoint exists: clusters in the user forms come from the users' cluster ids and
  are labelled "Cluster …c001". A `GET /v1/clusters` (or clusters in `/v1/catalog/stores`) would
  let the console show names.
- The users table fetches each user's devices for the "Device" column (one request per row,
  cached). Fine for pilot tenants; a `device_status` field on `UserOut` would remove it.
- Farmer / officer record links go to `/farmers/{id}` and `/field-team/{id}` (`RECORD_ROUTES`);
  the analytics branch owns those routes — adjust the map there if it uses other paths.
- Owner / watcher / actor names need `GET /v1/users` (owner, director, tenant admin, cluster head,
  auditor); store managers and field officers see roles instead of names.
- Logo: `/v1/uploads` is not open to owners / directors, so C102 takes a blob URI or https link;
  https / data images show in the preview, otherwise a monogram.
- Webhook replay window, legal name, GSTIN per state and invoice prefix live under "Credit and
  money"; consent and location policy versions under visits / duty.

## Tests

- Vitest (215 total, +47 here): `lib/step-up.test.ts` (retry after OTP with `X-Step-Up-Token`,
  token reuse, never persisted, cancel, 403 not prompted, forged token dropped, wrong code),
  `components/admin/StepUp.test.tsx` (dialog end to end, inline wrong code, cancel),
  `lib/flags.test.ts` (state machine action availability per role, notes, SLA countdown, query,
  geometry, record links), `lib/settings-form.test.ts` (rupees / minutes conversion, round trip,
  changed-keys patch, every range, GSTIN / prefix / colour / phone / languages, 422 mapping),
  `lib/admin.test.ts` + `components/admin/AuditDiff.test.tsx` (diff order and rendering).
- Playwright (16 total, +7 in `e2e/inbox-admin.spec.ts`): inbox groups, counts, owners, overdue
  timers in danger and ticking, filters; officer explanation; evidence map points / photos /
  records / metrics / summary box, start review -> escalate with a required note -> history and
  owner change; force logout needs step-up, token reused for a rebind and forgotten on reload;
  settings validation, live branding preview, step-up, "Saved and audited" -> filtered audit row
  with the before / after diff; audit filters, diff, CSV export behind step-up; cluster head nav
  and 403 states.
- `npm run check` (lint, string lint, typecheck, unit tests, build) and `npm run test:e2e` green.
