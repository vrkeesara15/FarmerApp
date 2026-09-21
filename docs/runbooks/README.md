# Runbooks (SPEC 12.5)

Every alert policy in `infra/modules/monitoring` names its owner, severity and one of these
runbooks in its documentation block (the link base is `runbook_base_url` in the env tfvars).
Each runbook has the same shape: owner, severity, detection signal, steps with exact
commands, verification, communication, follow-up. Rehearse each one in stg before the pilot.

| Runbook | Owner | Severity | Detection (alert) |
|---|---|---|---|
| [Platform incident: API / console down, errors, latency](platform-incident.md) | Platform lead | Sev 1 / 2 | OPS-001 uptime, OPS-002 error rate, SLO availability burn, SLO latency |
| [OTP provider outage and failover](otp-provider-outage.md) | Platform lead | Sev 1 | SLO OTP delivery < 95% / 10 min, WhatsApp fallback spike |
| [Payment webhook backlog (DLQ replay)](payment-webhook-backlog.md) | Platform lead + finance lead | Sev 1 | OPS-004 `payment.webhook` backlog / DLQ, OPS-001 webhook uptime |
| [Cloud SQL failover and restore](cloud-sql-failover-restore.md) | Platform lead | Sev 2, Sev 1 if sustained 30 min | OPS-003 CPU / storage / connections / replica lag |
| [Disaster recovery (NF-006) and quarterly drill](disaster-recovery.md) | Platform lead | Sev 1 | Region / instance loss, data corruption |
| [Scheduled job failure](job-failure.md) | Job owner (per alert) | Sev 2 | OPS-005 `job <name> failed` |
| [Bad mobile release rollback](bad-mobile-release-rollback.md) | Mobile lead | Sev 1 / 2 | Crashlytics crash-free < 99% (OPS-002), sync SLO burn |
| [Corpus rollback to previous version](corpus-rollback.md) | Agronomy lead / ML | Sev 2 | M6 evaluation job, agronomist reports (placeholder) |
| [Mass location anomaly](mass-location-anomaly.md) | Mobile lead | Sev 2 | OPS-006 sync-silence spike, officers-on-duty drop |
| [Data subject erasure request](data-subject-erasure.md) | Data protection owner | Sev 3 (SLA-bound) | Request received (support / grievance officer) |
| [Cost anomaly and budget](cost-and-budget.md) | Product owner + platform lead | Sev 2 | OPS-012 daily spend > 130% of the 7-day average, LLM / SMS spend per tenant, NF-015 budget thresholds |
| [Suspected data breach (DPDP notification)](suspected-data-breach.md) | Security owner | Sev 1 | SCC HIGH/CRITICAL (SEC-019), Cloud Armor spike, audit-log anomaly, report |
| [PII field encryption: setup, backfill, contract, rotation (SEC-026)](pii-encryption.md) | Platform lead | Sev 2 | `pii_data_key_unavailable`, `pii_backfill_conflict`, 500s on encrypted reads |
| [Datastream CDC setup, operation and teardown (M7, AN-010 / AN-014)](datastream-cdc-setup.md) | Platform lead + data owner | Sev 2, Sev 1 if the slot fills the disk | `dbt source freshness` error (> 30 min), stream not `RUNNING`, SQL disk growth (OPS-003) |

Reference: [observability.md](observability.md) — channels, severities, SLOs, dashboards and the
structured-log field contract the log-based metrics rely on.

Not alert-driven, but the same shape — a pipeline gate blocks a release instead of an alert
firing: [Mobile release security scan (SEC-008)](mobile-security-scan.md) (mobile lead) —
what the manifest, obfuscation, secret and MobSF gates in `mobile-release.yml` assert, how to
reproduce each on a local release APK, and how to record an accepted finding.

## Severity and channels (SPEC 12.3)

| Severity | Examples | Channel | Response |
|---|---|---|---|
| Sev 1 | outage, payment failure, data leak | page (phone / PagerDuty) + Slack `#farmerapp-ops` + e-mail | 15 min, 24x7 in sowing seasons |
| Sev 2 | degraded, job failure | Slack `#farmerapp-ops` + e-mail | next business hour |
| Sev 3 | business signals, data quality | daily digest to owners | next day |

Every Sev 1 gets a blameless postmortem in `docs/postmortems/` within 5 working days.

## Conventions used in the commands

```bash
ENV=prd                       # dev | stg | prd
PROJECT=farmerapp-$ENV
REGION=asia-south1
```

Only the platform lead (or delegate) runs state-changing commands in stg / prd. Nothing in
these runbooks deletes data without the data protection owner's written approval
(CLAUDE.md: no data deletion in shared environments by automation).
