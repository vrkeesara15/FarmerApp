# Runbook: scheduled job failure (OPS-005)

- **Owner:** the job owner named in the alert (`owner` label): platform lead, product owner (rules, flags), ops lead (duty, sync silence), finance lead (reconciliation)
- **Severity:** Sev 2 ticket, next morning
- **Detection:** `[env] job <name> failed (OPS-005, sev2)` from `run.googleapis.com/job/completed_execution_count{result="failed"}`

## Jobs (infra/envs/*/main.tf `local.jobs`, command `python -m farmerapp.jobs <command>`)

| Job | Schedule (IST) | Safe to re-run? |
|---|---|---|
| `run-rules-batch` | 02:00 daily | yes (dedupe key: no duplicate open flags) |
| `flags-sla-escalation` | hourly | yes (moves only flags past SLA) |
| `officer-sync-silence` | every 15 min | yes (one notification per session) |
| `auto-end-duty` | every 10 min | yes |
| `ensure-partitions` | 00:30 daily | yes (idempotent); **urgent** if it fails 2 days running: location inserts fail when today's partition is missing |
| `purge-location-points` | 04:00 daily | yes; `--apply` only in prd |
| `purge-expired` | hourly | yes |
| `reconcile-payments` | 06:00 daily | yes (dry run, notifies accountants) |
| `backfill-farm-photo-phash` | manual | yes (only unhashed photos) |
| `migrate` | each deploy | see [platform-incident.md](platform-incident.md) |

## Steps

1. Find the failed execution and its logs:
   ```bash
   JOB=<name>
   gcloud run jobs executions list --job $JOB --region $REGION --project $PROJECT --limit 5
   gcloud logging read "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"$JOB\" AND severity>=DEFAULT" \
     --project $PROJECT --freshness 1d --limit 100 --format='value(timestamp,textPayload,jsonPayload.event)'
   ```
2. Classify: code error (traceback) -> fix forward and deploy; database unavailable -> [cloud-sql-failover-restore.md](cloud-sql-failover-restore.md); timeout -> raise `timeout_seconds` for the job in Terraform; unknown tenant id -> fix `job_tenant_ids` in the env tfvars.
3. Re-run once the cause is fixed (same args as the schedule):
   ```bash
   gcloud run jobs execute $JOB --region $REGION --project $PROJECT --wait
   ```
   One tenant only, e.g. `--args="run-rules,--mode,batch,--tenant-id,<uuid>"` (overrides the args for this execution).

## Verification

- The re-run execution is `Succeeded`; the job's summary line (e.g. `run-rules (batch): tenant=... raised=...`) is in the logs.
- The alert auto-closes within 24 h.

## Communication

- Ticket in `#farmerapp-ops`; the owner confirms business impact (e.g. flags not raised last night, reconciliation not sent to finance).

## Follow-up

- Two consecutive failures of the same job: add a test reproducing it before the fix.
