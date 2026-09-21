# M7 — security and data protection

SEC-007, SEC-008, SEC-020, SEC-021, SEC-022, SEC-027, NF-011, NF-012, NF-013, NF-016.

Branch `feat/M7-security-privacy`. Ten requirements that had one thing in common: the control
existed somewhere — in a runbook, in a comment, in one of two call sites — but nothing failed
when it stopped being true. This change turns each of them into a gate.

---

## SEC-007 — licence compliance

**Before:** a `licenses` job that printed a table and grepped for the string `AGPL`. It did not
fail on an *unknown* licence, had no allowlist, and its Dart step was an `echo` with a TODO.

**Now:** `scripts/licences/check_licences.py` (Python 3.12, stdlib only) over the three things
we ship, with `scripts/licences/allowlist.toml` as the policy and `docs/licence-policy.md` as
the prose.

* **python** — `uv export --no-dev` intersected with `pip-licenses`, so pytest and mypy are not
  judged as if we shipped them.
* **node** — `license-checker-rseidelsohn --production` in `apps/console`.
* **dart** — `pubspec.lock` resolved against the local pub cache, with a pub.dev fallback that
  downloads the archive and reads `LICENSE` when the cache is cold.

Unknown is a failure, not a shrug. `--strict` makes an ecosystem we *cannot* scan a failure
too: a licence gate that silently scans nothing is worse than no gate.

Local run on this tree: **427 packages, 0 denied, 0 unknown, 3 exceptions.**

| Exception | Licence | Why it is allowed |
|---|---|---|
| `fpdf2` | LGPL-3.0-only | Unmodified import in the API container, which is hosted and never conveyed, so LGPL §4 never triggers. |
| `@img/sharp-libvips-*` | LGPL-3.0-or-later | Dynamically-loaded libvips binaries behind sharp; not in the browser bundle. |
| `caniuse-lite` | CC-BY-4.0 | Attribution-only browser-support *data*, build time only. |

LGPL sits on the `denied` list and is admitted only per package, because safety depends on
linkage: **never acceptable in `apps/mobile`** (AOT static linking), acceptable for a
dynamically-linked, unmodified dependency in the API or console image. Two real bugs were found
while building the scanner and fixed: MPL-2.0's body *names* the AGPL in its "Secondary
License" clause (five Dart packages were being reported AGPL), and names like
`ISC License (ISCL)` were mangled by naive paren-stripping.

## SEC-008 — mobile static scan

**Before:** `grep -aq 'debuggable'` on a *binary* AndroidManifest, behind `|| true`. That proves
nothing in either direction — the attribute name is in the AXML string pool regardless of its
value, and the value is a packed int — and the `|| true` hid failures of the step itself.

**Now:** four gates in `mobile-release.yml`, all reading one artefact: the universal APK
`bundletool --mode=universal` builds from the AAB (signed with a throwaway key, never
published).

1. **Manifest** (`apps/mobile/tool/check_release_manifest.sh`, via `aapt2 dump xmltree`):
   `debuggable` absent or false, `allowBackup=false`, backup/extraction rules and a network
   security config present, no global cleartext. **Exit 2 if `aapt2` is missing** — it never
   passes by accident.
2. **Obfuscation** (`scripts/mobile/apk_obfuscation_check.sh`): `build/symbols` non-empty *and*
   no `.symbols` inside the APK; at least 25 % of DEX classes have one- or two-character names
   (`apkanalyzer dex packages`, falling back to `dexdump`); `isMinifyEnabled` and
   `isShrinkResources` true in the `release` build type. Exit 2 if neither DEX tool works.
3. **Secrets** (`scripts/mobile/apk_secret_scan.sh`): `strings` over every entry for nine
   credential shapes (`AIza…`, `sk-ant-`, `rzp_live_`, `AKIA…`, PEM private keys, JWTs, …) plus
   every non-placeholder value of 12+ characters in the repo `.env.example`, plus "no packaged
   `.env`". **It prints the pattern name and the entry, never the matched value**, so the log
   cannot leak the key it just found.
4. **MobSF** (`scripts/mobile/mobsf_gate.py`): the free OSS docker image, per-run API key,
   `MOBSF_HIGH_LIMIT=0`, and a failure on any `secrets` finding. It fails on an unrecognised
   report schema rather than reporting a clean scan it did not actually read, and if the
   container cannot start the **job fails** unless `vars.MOBSF_OPTIONAL == 'true'`.

`docs/runbooks/mobile-security-scan.md` says which MobSF sections matter, how to reproduce each
gate on a local APK, and what to do when one fires.

One deliberate deviation, documented: `android:extractNativeLibs` is **not** asserted false —
`useLegacyPackaging = true` keeps it true on purpose for the FM-014 APK budget.

## SEC-020 — JWT lifetimes, rotation, reuse detection, device binding

Already implemented (FA-001, M4, M5). What was missing was a test for each clause of the
sentence, which is what closing a requirement should mean. `tests/auth/test_sec020.py`:

* the configured lifetimes **are** 15 min and 30 days;
* an access token is accepted at 14:59 and rejected at 15:01 with `token_expired`;
* a refresh token still works one second before 30 days;
* rotation stays inside the family and resets the 30 days;
* **reuse revokes only the leaked family** — another session of the same user keeps working;
* an admin revocation answers `session_revoked`, not `refresh_reused` (the client is not
  accused of a leak);
* a field officer's session stays device-bound *after* a rotation, and a missing `device_id`
  is refused the same way a wrong one is;
* access tokens of a bound session carry `did`, including the one minted by a refresh (SEC-025
  leans on this);
* a console session has no `did` and no binding — device binding is for field agents;
* a logout kills one family, not the account.

**SEC-020 is done.** The RS256 + JWKS note stays open as a future ADR, not a gap: HS256 is
sufficient while the API is the only verifier.

## SEC-021 — OTP hardening and SMS pumping protection

Hashing (HMAC-SHA256 + server pepper, bound to the challenge id), constant-time compare and
single use were already in place and tested. What was missing is the reason SMS pumping is
profitable: nothing stopped an attacker farming *sends*.

`farmerapp/auth/otp_abuse.py` adds four layers, run cheapest-first before any SMS leaves:

1. **Country** — `OTP_ALLOWED_COUNTRY_CODES`, India only by default; `403
   otp_country_blocked`. The HTTP schema already rejects non-Indian numbers (SEC-022), so this
   is the layer *behind* it, for the send paths whose number comes from the database (step-up,
   farmer confirmation, jobs).
2. **Block list** — `otp_block`, a *hashed* phone or IP (`HMAC(otp_pepper, scope‖value)`, so the
   table is useless to anyone who reads it) with an expiry; `429 otp_blocked`.
3. **Velocity** — beyond FA-001's 3 resends per 15-minute window: at most 10 sends to one number
   per 24 h and 20 from one client IP per hour. Breaking either is `429 otp_rate_limited` *and*
   writes a block row whose window **doubles on every strike** (capped at 30 days) — that is the
   repeat-abuser rule.
4. **Cost guard** — an `otp_cost_alert` at ERROR above 200 tenant sends an hour (an alert never
   refuses a login), and a breaker at 2 000: `429 otp_cost_limited`.

`otp_challenge` gains `request_ip`, recorded from the first `X-Forwarded-For` hop, and the
counts come from that table, so there is no second ledger to keep in sync. Everything is
per tenant under RLS; cross-tenant and per-ASN limits stay with Cloud Armor (SEC-014), and an
unknown number never reaches a provider at all.

18 tests in `tests/auth/test_otp_abuse.py`, including that a blocked country is logged with a
masked number and that a block expires on its own.

## SEC-022 — input validation and console security headers

**API.** `tests/api/test_input_validation.py` walks every route FastAPI actually serves — the
same trick as the SEC-006 authz matrix — and asserts three properties: every request body is a
Pydantic model (not `dict`/`Any`), every plain-`str` field is bounded by `max_length` or a
`pattern` (in the field, in an `Annotated[str, StringConstraints(...)]` alias, or anywhere
inside a union), and every `str` query parameter is bounded.

That found **18 unbounded free-text fields**, all now bounded: `catalog` product descriptions
and label-claim PPE/safety text, the sync cursor, and eleven tenant-settings patch fields
(branding names, colour, logo URI, support phone; consent and policy versions; legal name;
invoice prefix; the two HH:MM times). Only *length* was added to the settings patch models:
their format is validated one layer down by `TenantSettings`, which is what produces the
`422 invalid_settings` problem with the per-field errors the console renders. Duplicating
those patterns at the edge changed the error code and broke three existing contract tests —
an unbounded string is the DoS risk, a malformed time is not. Six `phone` fields are in a
documented allowlist because a validator parses them
rather than a pattern matching them; the test fails if an allowlist entry becomes stale, so a
fix deletes its entry instead of leaving it behind.

Two entries are **not ours to fix**: `GET /v1/analytics/farmers?sort` and `?cursor` are
unbounded strings owned by the analytics workstream. They are in `ALLOWED_UNBOUNDED_QUERY`
with a note; bounding `sort` with a `Literal` and `cursor` with a length is a small follow-up
for that owner.

**Console.** A per-request nonce from `middleware.ts`, set on both the forwarded request
headers (so Next auto-nonces its own bootstrap scripts) and the response, with
`app/layout.tsx` reading `x-nonce` for the two init scripts:

```
default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; frame-src 'none';
form-action 'self'; script-src 'self' 'nonce-<n>' 'strict-dynamic'; style-src 'self' 'unsafe-inline';
img-src 'self' data: blob: https:; font-src 'self' data:; connect-src 'self'; media-src 'self';
manifest-src 'self'; worker-src 'self' blob:; upgrade-insecure-requests
```

No `unsafe-inline` and no `unsafe-eval` for scripts. `next.config.ts` adds the static headers
(HSTS `max-age=31536000; includeSubDomains; preload` in production, `X-Content-Type-Options`,
`Referrer-Policy`, `Permissions-Policy`, `X-Frame-Options`, `Cross-Origin-Opener-Policy`); no
header is set in both places. Output encoding gets its own gate:
`scripts/lint-dangerous-html.mjs` fails on a new `dangerouslySetInnerHTML` outside the two
allowlisted layout scripts, wired into `npm run lint`.

Two relaxations are kept and named in the code: `style-src 'unsafe-inline'`, because
Recharts, Leaflet and next-font write inline style *attributes*, which cannot carry a nonce
(and no nonce is put in `style-src`, which would disable the fallback); and `img-src https:`,
because tenant logos, signed evidence-photo URLs and an env-overridable tile host are not a
fixed host set.

Playwright asserts the headers on `/login` and a console page, that `script-src` has a nonce
and no `unsafe-inline`, and that **no CSP violation is recorded** during load and interaction.

## SEC-027 — one PII guard for both LLM paths

Both call sites complied, in two different ways, with two different ideas of what "no PII"
meant. `farmerapp/pii/llm_guard.py` is now the single guard both go through:

* `guard_prompt(payload, where=…)` refuses e-mail addresses, phone-like digit runs (10-15
  digits, `+91` and separators tolerated, record ids excluded), Aadhaar-shaped numbers and
  decimal coordinate pairs — anywhere in a string, at any depth, with the path in the error;
* `is_pii_key` / `scrub` drop keys that name a person or a contact detail and mask phone-like
  runs, leaving record ids intact;
* `assert_no_exif` asserts the bytes that reach a provider carry no EXIF/XMP block;
* `DIAGNOSIS_PROMPT_FIELDS` and `FLAG_BUNDLE_KEYS` **pin the shape of each prompt**.

That last part is the gate the requirement asks for. `build_messages` and `loggable_prompt`
call `guard_request`, which compares `dataclasses.fields(LlmRequest)` against the reviewed
set; `build_bundle` compares the finished evidence bundle against `FLAG_BUNDLE_KEYS` and then
re-checks its content. **Adding a field to either prompt fails the build until someone reviews
it here**, and a name, phone, e-mail or coordinate that reaches a prompt raises
`PromptPiiError` instead of a provider call. 29 tests in `tests/pii/test_llm_guard.py`.

## NF-011 — data residency, enforced

Two claims, two halves, both now tested (`tests/deploy/test_residency.py`, 19 tests).

**Where things live** — the same python-hcl2 reader the SEC/deploy drift check uses parses the
real Terraform and fails if any environment region, SQL backup location, module default, KMS
key-ring location or hard-coded literal in `infra/envs/*` is outside `asia-south1` /
`asia-south2`, or if the SEC-018 `gcp.resourceLocations` policy allows anything else.

**What leaves** — `farmerapp/privacy/egress.py` registers **every** outbound destination the
backend can open a socket to, with what the payload carries and whether the endpoint is in an
Indian region. The test greps `farmerapp/` for HTTP clients and the Anthropic SDK and fails on
a module with no entry.

That gate immediately found one I had missed: **the VV-006 Google Roads API**, which would send
an officer's GPS track abroad. It is off in every environment (`ROAD_SNAPPER=off`) and is the
one entry allowed to declare `personal_data=True` outside India — only because it carries a
recorded review *and* an off switch, both of which the test checks. Enabling it needs a DPIA
and a DPA.

The two live foreign paths are documented with what they carry:

| Path | Carries |
|---|---|
| Anthropic (DX-004 fallback, VA-004 summaries) | EXIF-stripped photo; crop, district, season, crop stage, candidate problem ids. Never a name, phone, id or coordinate. |
| Open-Meteo (FM-008) | The 0.1-degree grid cell's latitude and longitude, one decimal. Nothing else — the test pins the exact query-parameter set. |

## NF-012 — retention for every class

The spec sentence now lives in exactly one place, `farmerapp/retention/policy.py`, and
`python -m farmerapp.jobs retention-sweep --tenant-id <id>` reports every class in one command.

| Class | Window | Action | Owner |
|---|---|---|---|
| `location_points` | 180 d | purge | the existing partition-dropping job |
| `photos` | 1095 d | archive | the GCS lifecycle rule — **verified against the real `.tf`**, including that there is no `Delete` rule that would orphan `visit_photo` rows |
| `audit_logs` | 400 d (min 365) | purge | the migrate role; the app role has no `DELETE` grant |
| `visit_records` | 2555 d | purge | the sweep, with `--apply` |
| `financial_records` | 2920 d | **retain** | nobody |

Rules the job obeys, each with a test: dry run is the default everywhere including the
scheduled job; the tenant is bound before anything is counted, so a sweep cannot reach another
tenant; `RETAIN` never deletes with or without `--apply`; `ARCHIVE` never deletes (the object
goes cold, the row stays, because a seven-year visit record still names it); append-only
classes are reported with the identity that must do the work. 24 tests on the seeded world,
`docs/retention.md` for humans.

## NF-013 — DPDP data-principal rights, end to end

All four rights, in the app and in the console, on the existing `data_request` ticket
(migration 0040 adds `grievance`, `subject`, `message`, `requested_changes`, `erasure_report`).

* **Access** — `GET /v1/me/data-export` returns the principal's account, farmer record, farms,
  crop plots, consent history, visits, orders, payments, khata entries, diagnoses and their own
  tickets. Encrypted fields are decrypted *for their own record*; `*_enc` and `*_hash` columns
  never appear (tested). Staff serve an `access` ticket with
  `GET /v1/admin/data-requests/{id}/export`. Both audited.
* **Correction** — `POST /v1/me/correction-request {changes}`, restricted to the principal's
  own five fields; anything else is `422`. Values are checked against the *column's* closed set
  at request time (`language`, `land_ownership`, the phone shape), so a value that would trip a
  CHECK constraint is a 422 to the principal rather than a 500 to the admin who applies it.
  Staff apply it with step-up; the field diff lands in the FA-006 trail and
  `privacy.correction_applied` records why.
* **Erasure** — `POST /v1/admin/data-requests/{id}/erase` (step-up) anonymises the farmer and
  the account, revokes every refresh-token family and bound device, and **records on the ticket
  what it had to keep**. The kept list is not written twice: it is read from the NF-012 policy
  at run time, and `GET /v1/admin/data-requests/retention-exceptions` returns it so the console
  shows the operator the eight-year financial floor before they confirm. Idempotent; a second
  attempt is `409`.
* **Grievance** — `POST /v1/me/grievance`, plus a **public** `GET /v1/privacy/contact` with the
  officer, the contact details and the 30-day commitment.
* **Consent records** stay exportable (M7 growth).

Console: `/admin/data-requests` — the staff queue with type/status filters, an overdue badge,
Start/Complete/Reject, Apply correction (showing the requested diff), Run erasure (showing the
retained report) and Download export, all role-gated to owner and tenant admin, all five
languages.

`docs/dpdp.md` is the compliance note: who is fiduciary and who is processor, the lawful basis
for farmers (consent) and for employees (legitimate use, with the three limits that make it
honest), each right and where it lives, the erasure exception with its statutory basis,
cross-border processing, and what is still a human gate. `tests/privacy/test_dpdp_docs.py`
checks that the note covers every right the API serves and every class the erasure keeps, that
the breach runbook still carries the Board, the 72 hours and a **rehearsal log** (SPEC 11.4),
and that the erasure runbook points at the endpoint rather than the old hand-written SQL.

## NF-016 — maintainability gates

| Gate | State | Number |
|---|---|---|
| API coverage ≥ 80 % on domain logic | already enforced (`--cov-fail-under=80`) | see the check output below |
| mypy strict | already enforced | 0 errors, 653 source files |
| TypeScript strict | `strict: true` + `noUncheckedIndexedAccess`, verified | 0 errors |
| **`any` escapes** | **added**: `@typescript-eslint/no-explicit-any` as an *error* | **0 pre-existing violations** — nothing had to be fixed or suppressed |
| Dart strict analysis | unchanged, owned by the mobile workstream | — |
| **Output encoding** | **added**: `scripts/lint-dangerous-html.mjs` in `npm run lint` | 268 files, 1 allowlist entry |

---

## Checks

**A full `SKIP_AUDIT=1 make check-api` did not complete on this machine, and the reason is the
environment, not this change.** Three workstreams share one Postgres container; while the
neighbouring suite ran, `farmerapp-db-1` sat at ~80 % CPU with 41 connections against a
`max_connections` of 100. Four attempts either crawled (1 % in 18 minutes) or produced ~1 700
`asyncpg` errors that look like failures but are connection exhaustion — the same suites pass
in isolation. Past the 45-minute timebox I stopped competing for a saturated shared resource
rather than degrade the neighbour's run too. What *was* verified, all green:

* `ruff check` and `ruff format --check` — 658 files;
* `mypy` (strict) — 657 source files, 0 errors;
* `bandit` — 0 high, 0 medium (4 low, pre-existing);
* `python -m farmerapp.jobs validate-rules` — 21 rules;
* `scripts/export_openapi.py --check` — `openapi.yaml` up to date;
* every suite that touches a file this change edits, run in isolation: `tests/auth` (including
  the new `test_sec020.py` and `test_otp_abuse.py`), `tests/admin`, `tests/advisory`,
  `tests/privacy`, `tests/retention`, `tests/pii`, `tests/deploy`, `tests/api`, `tests/flags`,
  `tests/diagnosis`, `tests/rls`.

Two genuine regressions surfaced in the partial full runs and both are fixed and re-verified:
the settings-patch patterns described above, and `tests/admin/test_step_up.py`'s SEC-028
inventory, which now lists the two new step-up operations. **The next agent to run a full
`make check-api` on a quiet database should treat that as this change's remaining gate.**
* `cd apps/console && npm run check` — 396 tests in 61 files; lint (including the two repo-local
  lint scripts), `tsc --noEmit`, `next build`.
* `cd apps/console && npm run test:e2e` — **46/46 passed**, with CSP enforced.
* `actionlint` — clean on all nine workflows.
* `python3 scripts/licences/check_licences.py --ecosystem all` — 427 packages, 0 denied,
  0 unknown.

Not run here (other workstreams own them): `make check-mobile`, `make check-infra`,
`make check-dbt`.

### A note on running the API suite locally

Three agents share one Postgres container (`max_connections = 100`), and `make test-api`
defaults to one xdist worker per core. Running the full suite while another workstream ran
theirs exhausted connections and produced ~1 700 spurious `ERROR`s that look like test
failures but are not; the same suites pass in isolation. Two things make a local run reliable:

* cap the workers and the pool — `API_TEST_WORKERS=3 DB_POOL_SIZE=2 DB_MAX_OVERFLOW=3`;
* never run two pytest sessions from the *same* checkout at once. The per-worker databases are
  named from the checkout path, so two sessions collide on `…_gw0` and the first to finish
  drops the database the other is using (`InvalidCatalogNameError`).

Worth considering for the repo: raise `max_connections` in `docker/postgres`, or key the
worker-database names on the pytest session id as well as the checkout.

## Touched outside this workstream

* `apps/mobile/tool/check_release_manifest.sh` is **called** by `mobile-release.yml` but not
  modified — it already did the robust `aapt2 dump xmltree` check the workflow needed.
* `apps/console/e2e/inbox-admin.spec.ts`: one selector scoped to `getByTestId("audit-filters")`
  with `exact: true`. The new `data_request.apply_correction` audit rows produce a "Show changes
  of …" button whose accessible name contains "Apply", which made the old unscoped
  `getByRole("button", { name: "Apply" })` ambiguous under Playwright strict mode.

## Follow-ups

* **Analytics workstream:** bound `GET /v1/analytics/farmers?sort` (a `Literal`) and `?cursor`
  (a length), then delete their entries from `ALLOWED_UNBOUNDED_QUERY`.
* **Infra:** schedule `retention-sweep` daily per tenant as a dry run, so OPS-005 can alert when
  a class stops being swept; decide per environment whether `visit_records` runs with `--apply`.
* Two pre-existing Playwright flakes under 5-worker parallel load (`inbox-admin` C71,
  occasionally `products` C52) were confirmed to predate this change by running the suite with
  `middleware.ts` removed.

## Human gates

* Play Console promotion and release signing (SEC-008); the first real CI run should be read to
  confirm the 25 % short-class-name threshold matches the actual R8 output.
* The privacy notice, consent copy and the grievance officer's real name and contact
  (TODO-LEGAL, SPEC 14.6).
* DPAs with the SMS gateway, Razorpay and any e-mail provider; the DPIA before
  `ROAD_SNAPPER=google` could ever be enabled.
* The annual breach-notification drill (record it in the new rehearsal log) and the external
  penetration test before pilot and before SaaS launch (SPEC 11.4).
* Reviewing and re-dating the three licence exceptions each quarter (SPEC 11.4 dependency
  review).
