# Runbook: data subject erasure request (DPDP Act 2023)

- **Owner:** data protection owner (DPO / grievance officer), executed by the platform lead
- **Severity:** Sev 3, SLA-bound (acknowledge within 2 working days; complete within the period set by the DPDP Rules and the privacy notice — TODO-LEGAL: confirm the number of days with counsel)
- **Detection:** request from a farmer (app "Delete account", FM-015, when built), a field officer on the farmer's behalf, a tenant owner, e-mail to the grievance officer, or the Data Protection Board.

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
5. Execute (until FM-015 automates it): a reviewed SQL script, run by the platform lead in one transaction on the primary, with the tenant scope set (`SELECT set_config('app.tenant_id', '<tenant>', true)`), that deletes or pseudonymises the rows found in step 3; the product owner or DPO approves the script in the ticket first. Then remove the photos:
   ```bash
   gcloud storage rm gs://farmerapp-$ENV-photos/<tenant>/<farmer-id>/**   # after DPO approval; list first with `gcloud storage ls`
   ```
   Revoke sessions if the person had a login: `POST /v1/users/{id}/force-logout` (audited).
6. Confirm Datastream propagated the deletes (BigQuery `raw` row count for the farmer id = 0 after the CDC lag, OPS-011).

## Verification

- Queries from step 3 return no personal data (only pseudonymised statutory records).
- The audit trail shows who ran the erasure and when (`audit_log`, Cloud Audit Logs Data Access for GCS).

## Communication

- Written response to the data principal (and the tenant): what was erased, what was retained and why, when backups expire.

## Follow-up

- Close the ticket in the privacy register; FM-015 (delete account) automates steps 3-6.
