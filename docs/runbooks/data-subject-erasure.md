# Runbook: data subject erasure request (DPDP Act 2023)

- **Owner:** data protection owner (DPO / grievance officer), executed by the platform lead
- **Severity:** Sev 3, SLA-bound (acknowledge within 2 working days; complete within the period set by the DPDP Rules and the privacy notice — TODO-LEGAL: confirm the number of days with counsel)
- **Detection:** request from a farmer (app "Delete account", FM-015 — `POST /v1/me/deletion-request`), a field officer on the farmer's behalf, a tenant owner, the grievance channel (`POST /v1/me/grievance`, contact at `GET /v1/privacy/contact`), e-mail to the grievance officer, or the Data Protection Board. Every route lands in the same queue: console **Admin -> Data requests**, `GET /v1/admin/data-requests`, oldest due first, with a 30-day deadline and an overdue badge.

Who is the fiduciary: for farmer data captured by a tenant (agri-retailer), the tenant is the
data fiduciary and FarmerApp is its processor; the request is executed on the tenant's
instruction unless the farmer used the FarmerApp farmer app directly (then FarmerApp is the
fiduciary for that account). Record which case applies in the ticket.

## Steps

1. Log the request in the privacy register (ticket): requester, channel, date, tenant, data principal's phone (masked in chat: `+91******1234`).
2. Verify identity: OTP to the registered phone (the same flow as login) or, for a request made through the tenant, the tenant owner's written confirmation. Do not act on an unverified request.
3. Locate the data (read-only, as an admin with the tenant scope set; RLS stays on):
   - Postgres: `farmer` (+ `farm`, `crop_plot`, `visit`, `visit_photo`, `consent`, `order`, `payment`, `khata_entry`, `invoice`, `flag`), `user` if they have a login, `otp_challenge`, `refresh_token`.
   - GCS: photo objects referenced by `farm_photo` / `visit_photo` (`gs://farmerapp-$ENV-photos/<tenant>/...`).
   - BigQuery (Datastream CDC): `raw` / `marts` datasets receive deletes from CDC; the `views` dataset excludes PII.
   - Logs: phone numbers are masked in logs (`mask_phone`); audit log bucket entries are retained 400 days by law-enforced lock (SEC-017) and are exempt.
   - Backups: automated backups age out in 30 days (prd) / 7 days; they are not edited. Say so in the response.
4. Decide what must be retained: tax invoices and payment records are kept for the statutory period (GST: 8 years — TODO-LEGAL confirm) with the person pseudonymised (name / phone / address replaced, ids kept). Everything else is erased.
5. **Execute.** Since M7 this is one reviewed action in the console, not a hand-written SQL
   script. On the ticket, press **Run erasure**; the operator re-authenticates with an OTP
   (SEC-028) and the API runs `POST /v1/admin/data-requests/{id}/erase`
   (`farmerapp/privacy/erasure.py`), which in one transaction:
   - overwrites the farmer's name, phone and landmark, turns marketing consent off and soft
     deletes the row;
   - overwrites the login account's name and phone, disables it, revokes every refresh-token
     family and every bound device (so no session survives and no OTP can reach the number);
   - records, on the ticket, exactly which fields were anonymised and which record classes
     were kept and why (`erasure_report`), and writes a `privacy.erasure` audit entry.

   The response is what you quote back to the data principal. Read the **retained** list to
   them before you confirm: financial records 8 years, visit records 7 years, audit logs 1
   year, consent records append-only — the reasons are in
   [docs/dpdp.md](../dpdp.md#the-erasure-exception), and the console shows the same list
   (`GET /v1/admin/data-requests/retention-exceptions`).

   The run is idempotent; a second attempt on a closed ticket answers `409 invalid_transition`.

   Still manual, after the run: the photo objects, which the erasure does not touch because a
   seven-year visit record still names them. Remove them only when the DPO has approved it in
   the ticket, and list before you delete:
   ```bash
   gcloud storage ls   gs://farmerapp-$ENV-photos/<tenant>/<farmer-id>/**
   gcloud storage rm   gs://farmerapp-$ENV-photos/<tenant>/<farmer-id>/**   # after DPO approval
   ```

6. Confirm Datastream propagated the deletes (BigQuery `raw` row count for the farmer id = 0 after the CDC lag, OPS-011).

## Verification

- `GET /v1/admin/data-requests/{id}/export` (the access-right document for the same
  principal) shows the anonymised name and the reserved `+9170000…` phone, and the financial
  sections still list their rows — that is the whole policy in one response.
- Queries from step 3 return no personal data (only pseudonymised statutory records).
- The audit trail shows who ran the erasure and when: `privacy.erasure` in `audit_log`, plus
  the FA-006 field diffs on `farmer` and `user`, and Cloud Audit Logs Data Access for GCS.
- The ticket is `completed` with `handled_by` / `handled_at` set and an `erasure_report`.

## Communication

- Written response to the data principal (and the tenant): what was erased, what was retained and why, when backups expire.

## Follow-up

- Close the ticket in the privacy register. Steps 3-5 are automated (NF-013, M7); what is
  left by hand is identity verification, the photo objects and the written response.
- If the principal disputes a retained class, do **not** delete it: escalate to the data
  protection owner, who answers with the statutory basis in
  [docs/dpdp.md](../dpdp.md#the-erasure-exception). The eight-year financial window is a legal
  floor and nothing in the codebase can shorten it.
- Confirm the retention sweep still reports the tenant as compliant:
  `python -m farmerapp.jobs retention-sweep --tenant-id <tenant>` (dry run;
  [docs/retention.md](../retention.md)).
