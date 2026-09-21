# DPDP compliance note (NF-013, NF-011)

What FarmerApp does about the Digital Personal Data Protection Act 2023, where each piece
lives in the code, and what is still a human gate.

> **This is an engineering record, not legal advice.** The consent text, the privacy notice
> and the grievance officer's name are a legal review (SPEC 14.6, marked TODO-LEGAL). This
> document says what the software does; a lawyer says whether that is enough.

## Who is who

| DPDP term | Here |
|---|---|
| Data fiduciary | The tenant (the agri-input company). Each tenant decides why farmer data is processed. |
| Data processor | FarmerApp, running the platform on the tenant's behalf. |
| Data principal | The farmer, and the tenant's employees (officers, store staff). |
| Personal data | Name, phone, address/landmark, farm boundaries, on-duty location, photos, orders, payments, credit. |

Tenants are isolated by row-level security keyed on `app.tenant_id` (SEC-012), so one
fiduciary's data is never visible to another.

## Lawful basis

**Farmers — consent.** FM-002: a farmer is registered only after consent is recorded, and the
record is append-only (`consent_record`; a withdrawal is a *new* row, never an update). Two
purposes are separate: `data` (running the service) and `marketing`. Withdrawing marketing
consent does not withdraw service consent. The full history is exportable:
`POST /v1/exports {resource: "consent_records"}` (owner, director, tenant admin, auditor;
step-up, audited).

**Employees — legitimate use (section 7(i), employment).** An officer's on-duty location, duty
sessions and travel claims are processed to run the employment relationship: attendance,
travel reimbursement (FA-023), and verifying that a visit happened where it is claimed
(VV-001…VV-010). Three limits make that basis honest and all three are enforced in code:

* location is collected **only on duty** (FA-010) — the app stops sampling when duty ends and
  the API rejects points outside a duty session;
* the officer must accept the location policy before duty can start, and the accepted version
  is recorded (`policy_acceptance`, append-only, FA-011 / VV-010);
* raw points live **180 days** (NF-012); after that only daily aggregates remain.

There is no hidden tracking anywhere in the codebase, and `CLAUDE.md` forbids adding any.

## The four rights

Every right is reachable in two places: the app (`/v1/me/*`) and the console
(`/v1/admin/data-requests/*`, screen `/admin/data-requests`). Every request becomes a ticket
in `data_request` with a 30-day due date, so the commitment and its deadline are auditable.
`GET /v1/privacy/contact` is public and returns the grievance officer, the contact details and
the list of rights.

### Access

* `GET /v1/me/data-export` — the principal, in the app, gets a JSON document with their
  account, farmer record, farms, crop plots, consent history, visits, orders, payments, khata
  entries, diagnoses and their own data requests. Encrypted fields are decrypted *for their
  own record* — that is the point of the right — and the internal ciphertext and search-hash
  columns (`*_enc`, `*_hash`) are never included.
* `GET /v1/admin/data-requests/{id}/export` — staff serving an `access` ticket for a principal
  who asked by phone or in the store.
* Both are audited as `privacy.access_export`.
* The sections are declarative (`farmerapp/privacy/export.py`); a new table holding personal
  data is added there, and a test fails if a section names a column that does not exist.

### Correction

* `POST /v1/me/correction-request {changes: {field: value}, reason?}` — the principal asks.
  Only the principal's *own* fields may be asked for: `name`, `phone`, `landmark`, `language`,
  `land_ownership`. A request naming anything else (role, status, village, ids, money) is
  `422 validation_error`: a correction ticket is not an authorisation to edit the database.
* `POST /v1/admin/data-requests/{id}/apply-correction` — staff apply it, after re-auth
  (SEC-028 step-up). The change is written to the farmer and/or user record, the FA-006 audit
  trail records the field diff, and `privacy.correction_applied` records *why* it changed.

### Erasure

* `POST /v1/me/deletion-request` (FM-015; already in both apps) raises the ticket.
* `POST /v1/admin/data-requests/{id}/erase` (owner / tenant admin, step-up) runs it.

<a id="the-erasure-exception"></a>
Erasure here means **anonymisation plus retention of what the law requires**, and the console
shows the operator exactly that split before they confirm:

*Anonymised now, irreversibly:* the farmer's name, phone and landmark; marketing consent off;
the login account's name and phone; the account disabled; every refresh-token family revoked
and every bound device revoked, so no session survives and no OTP can be sent to the number
again (SEC-020, SEC-025).

*Kept, with the reason recorded on the ticket:*

| Kept | For | Why |
|---|---|---|
| Financial records — orders, order lines, payments, invoices, khata entries, day closes | 8 years | Section 128 of the Companies Act and the GST rules (NF-012). They keep pointing at the now-anonymised farmer row, so the books balance and the person is not identifiable from them. |
| Visit records | 7 years | Evidence of the advice the company gave, not a profile of the person; they reference ids, not names. |
| Audit logs | 1 year minimum | The record of who did what, including the erasure itself. |
| Consent records | append-only | The proof that consent was given and withdrawn *is* the record of lawfulness. |

This is the documented exception the spec asks for. The list is not written twice: it is read
from the NF-012 retention policy at run time (`farmerapp/privacy/erasure.retained_classes`),
and `GET /v1/admin/data-requests/retention-exceptions` returns it so the console can show it.

The run is idempotent (a second attempt on a closed ticket is `409 invalid_transition`) and
audited as `privacy.erasure`.

Operational steps, including what to do when the principal disputes the retained classes:
[docs/runbooks/data-subject-erasure.md](runbooks/data-subject-erasure.md).

### Grievance

* `GET /v1/privacy/contact` (public) — the grievance officer's name, e-mail, phone, and the
  30-day response commitment. Configured by `GRIEVANCE_OFFICER_*` (not secrets).
* `POST /v1/me/grievance {subject, message}` — a ticket of type `grievance` in the same queue,
  with the same deadline; tenant admins are notified (`data_request_received`).

## Notice and consent

FM-002 (farmer registration) shows the notice and records consent per purpose before any
personal data is stored. The consent text version is a tenant setting (`consent_version`) and
the version the principal saw is stored on the consent row, so a later text change does not
silently rewrite history. The notice copy itself is a legal review (TODO-LEGAL).

## Cross-border processing

NF-011: all personal data is stored and processed in `asia-south1` / `asia-south2`. Both halves
are enforced rather than asserted:

* **Storage and processing** — `apps/api/tests/deploy/test_residency.py` parses the real
  Terraform (`infra/envs/*`, `infra/modules/*`, `infra/bootstrap`) and fails if any region,
  location, SQL backup location, KMS key ring or module default is outside those two regions,
  or if the SEC-018 `gcp.resourceLocations` organisation policy allows anything else.
* **Egress** — `apps/api/farmerapp/privacy/egress.py` registers every outbound destination the
  backend can open a socket to, with what the payload carries. The test fails if a module
  opens an HTTP client without an entry, and refuses any destination outside an Indian region
  that carries personal data unless it has a recorded review *and* an off switch.

Two destinations are outside an Indian region and live:

| Destination | Carries | Control |
|---|---|---|
| Anthropic (DX-004 diagnosis fallback, VA-004 flag summaries) | The photo, re-encoded so no EXIF or GPS block survives, plus crop, district, season, crop stage and candidate problem ids. Never a name, phone, id or coordinate. | The shared guard `farmerapp.pii.llm_guard` refuses the call if anything person-shaped is in the prompt (SEC-027); prompts and outputs are logged to `llm_call_log`, kept one year. |
| Open-Meteo (FM-008 forecast) | The latitude and longitude of the farm's 0.1-degree grid cell (about 11 km), rounded to one decimal, and nothing else. No farm polygon, no farmer, no id, no key. | Grid rounding in `WeatherProvider.params`; the apps never call the provider, only the server does. |

A third, the Google Roads API (VV-006 track snapping), *would* carry an officer's GPS track. It
is **off in every environment** (`ROAD_SNAPPER=off`) and may not be enabled without a recorded
DPIA and a data-processing agreement. The egress register holds that decision and the test
fails if the default ever stops being `off`.

Everything else stays in the project's own Indian region (Cloud SQL, GCS, KMS, Pub/Sub, the
embed service) or goes to a contracted Indian provider (the OTP SMS / WhatsApp gateway,
Razorpay — an RBI-regulated Indian payment aggregator).

## Security of processing

| Control | Where |
|---|---|
| Phone numbers and addresses encrypted at field level (Cloud KMS envelope, key in `asia-south1`), with a searchable hashed phone column | SEC-026, `farmerapp/pii/`, [runbook](runbooks/pii-encryption.md) |
| Row-level security per tenant, forced, tested in CI | SEC-012, `farmerapp/db/rls.py` |
| Every endpoint role-checked, with an authz test per role | SEC-006, `tests/authz/test_matrix.py` |
| Access tokens 15 min, refresh 30 days with rotation and reuse detection, device-bound for field agents | SEC-020, `tests/auth/test_sec020.py` |
| OTP hashed at rest, constant-time compare, single use, SMS-pumping protection | SEC-021, `farmerapp/auth/otp_abuse.py` |
| Input validated by Pydantic models with bounded strings; strict CSP and security headers in the console | SEC-022, `tests/api/test_input_validation.py`, `apps/console/middleware.ts` |
| Admin actions re-authenticated and audited | SEC-028 |
| Audit trail of every write, append-only, 1 year minimum | FA-006, NF-012 |

## Breach notification

The DPDP Act requires notifying the Data Protection Board and every affected data principal.
The runbook is [docs/runbooks/suspected-data-breach.md](runbooks/suspected-data-breach.md):
detection signals, the containment steps, the assessment that decides whether it is a
reportable personal-data breach, the notification templates and timelines, and the owner.
SPEC 11.4 requires it to be tested once a year; record each test at the bottom of that runbook.

## What is still a human gate

* The privacy notice, the consent text and the grievance officer's real name and contact
  (TODO-LEGAL, SPEC 14.6).
* Signing DPAs with the SMS gateway, Razorpay and any e-mail provider before `EMAIL_PROVIDER`
  is set to a real one.
* The DPIA that would be needed before enabling `ROAD_SNAPPER=google`.
* The annual breach-notification drill, and the external penetration test before pilot and
  before SaaS launch (SPEC 11.4).
* Deciding, per tenant, whether `visit_records` purging runs with `--apply` in prd.
