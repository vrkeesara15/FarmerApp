# Runbook: suspected data breach (DPDP notification)

- **Owner:** security owner (incident commander); DPO for notifications; platform lead for containment
- **Severity:** Sev 1 (data leak), page
- **Detection:** SCC HIGH / CRITICAL finding on the `scc-findings` topic (SEC-019, `infra/bootstrap/security.tf`), Cloud Armor deny spikes, OTP send spikes (SMS pumping, OPS-013), unusual Data Access in the audit log bucket (SEC-017), a leaked credential (gitleaks, provider notice), or an external report (security@, a customer, CERT-In).

Legal clocks (TODO-LEGAL: confirm with counsel before the pilot and keep the contact list current):
- **CERT-In** (Directions of 28 April 2022): report cyber security incidents within **6 hours** of noticing them.
- **DPDP Act 2023 s.8(6) + DPDP Rules**: intimate the **Data Protection Board** and **each affected Data Principal** of a personal data breach without delay; the detailed report to the Board within **72 hours** of becoming aware. When FarmerApp acts as a processor, notify the tenant (fiduciary) immediately so it can notify; the contract sets who files.

## Steps

1. Open the incident: Sev 1 channel, incident commander named, timeline doc started (UTC and IST). Preserve evidence: do not delete logs, instances or buckets.
2. Triage what is exposed: which tenants, which data (phone, name, address, location, photos, payments), how many principals, since when. Sources:
   ```bash
   # Data Access / admin audit trail (locked bucket, 400 days)
   gcloud logging read 'logName:"cloudaudit.googleapis.com"' --bucket farmerapp-audit --location $REGION \
     --view _AllLogs --project $PROJECT --freshness 7d --limit 200 \
     --format='value(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.methodName,protoPayload.resourceName)'
   # Who can read the buckets / secrets right now
   gcloud storage buckets get-iam-policy gs://farmerapp-$ENV-photos
   gcloud secrets get-iam-policy jwt-signing-key --project $PROJECT
   ```
   Plus the app audit log (`audit_log` table, FA-006) for exports and role changes (SEC-028).
3. Contain (platform lead, each step recorded):
   - Leaked secret: add a new version and disable the old one (human, SEC-013), then new revisions so services read it: `gcloud secrets versions add <id> --data-file=- ...`, `gcloud secrets versions disable <old> --secret <id> ...`, `gcloud run services update api --update-env-vars ROTATED_AT=...`. JWT signing key rotation logs every user out.
   - Compromised account: disable it and force logout (`POST /v1/users/{id}/force-logout`, device report-lost for devices, SEC-025 remote wipe).
   - Hostile traffic: Cloud Armor deny rule for the source ranges (priority 1500).
   - Exposed object: confirm `public_access_prevention = enforced` still holds (`gcloud storage buckets describe gs://... --format='value(iamConfiguration)'`).
4. Assess: personal data breach yes / no (DPO decides, with the evidence); list the categories and number of Data Principals per tenant.
5. Notify (DPO):
   - CERT-In within 6 h of noticing (incident form, e-mail incident@cert-in.org.in).
   - Tenant(s) affected, immediately (they are the fiduciary for their farmers).
   - Data Protection Board: intimation without delay; detailed report within 72 h (nature, extent, timing, likely impact, mitigation, remedial steps, the person to contact).
   - Each affected Data Principal, in plain language and in their app language (te / kn / hi / mr / en): what happened, likely consequences, what we did, what they can do, contact. Channel: SMS / WhatsApp through the notify path, approved text only.
6. Eradicate and recover: patch, rotate, redeploy; verify SCC findings are resolved.

## Verification

- The access path is closed (re-test), secrets rotated, no further anomalous access in the audit log for 72 h.
- Every notification sent is recorded with time and content.

## Communication

- Internal: incident channel only; no speculation in customer channels. External statements go through the DPO / founders.

## Follow-up

- Postmortem within 5 working days; yearly rehearsal of this runbook (SPEC 11.4: incident response runbook tested once a year).
- SCC setup (human gate): activate Security Command Center Standard on the organisation, set `scc_notifications_enabled = true` and `org_id` in `infra/bootstrap`, and connect the `scc-findings.security-channel` subscription to the security Slack channel (relay needs a Slack webhook, created by a human).

## Rehearsal log

SPEC 11.4 requires this runbook to be tested once a year, and NF-013 requires it to exist at
all. A rehearsal is a table-top walk of steps 1-6 with the owner and one engineer, against a
made-up finding, timing how long each step takes and writing down what was unclear. Record
every drill here — an empty table is itself the finding.

| Date | Scenario | Participants | Time to step 4 (assess) | What we changed afterwards |
|---|---|---|---|---|
| _(none yet)_ | | | | |

Related: [docs/dpdp.md](../dpdp.md) (what the Act requires of us and where each control lives),
[data-subject-erasure.md](data-subject-erasure.md) (the request path, which a breach often
triggers a wave of).
