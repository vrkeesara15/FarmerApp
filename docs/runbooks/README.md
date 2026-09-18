# Runbooks (SPEC 12.5 — write before pilot)

Every alert in `infra/modules/monitoring` links here. Each runbook has an owner and is a TODO stub
until it is written and rehearsed before the pilot.

| Runbook | Owner | Related |
|---|---|---|
| [OTP provider outage and failover](otp-provider-outage.md) | Platform lead | SLO OTP delivery, OPS-013 |
| [Payment webhook backlog](payment-webhook-backlog.md) | Platform lead / Finance | OPS-004, OPS-008 |
| [Cloud SQL failover and restore](cloud-sql-failover-restore.md) | Platform lead | OPS-003 |
| [Bad mobile release rollback](bad-mobile-release-rollback.md) | Mobile lead | OPS-002 |
| [Corpus rollback to previous version](corpus-rollback.md) | Agronomy lead / ML | DX-011 |
| [Mass location anomaly](mass-location-anomaly.md) | Mobile lead | VV-001, OPS-006 |
| [Data subject erasure request](data-subject-erasure.md) | Data protection owner | FM-015 |
| [Suspected data breach (DPDP notification)](suspected-data-breach.md) | Security owner | OPS-013, SEC-019 |

Sev 1 incidents get a blameless postmortem in `docs/postmortems/` within 5 working days (SPEC 12.3).
