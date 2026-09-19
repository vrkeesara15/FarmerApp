# Runbook: Cloud SQL failover and restore

- **Owner:** platform lead
- **Severity:** Sev 2 ticket after 5 min, Sev 1 page when sustained 30 min (OPS-003); Sev 1 for primary down or data corruption
- **Detection:** `[env] Cloud SQL CPU > 80% | storage > 80% | connections > 80% | replication lag > 60 s (OPS-003, sev2 ticket / sev1 page)`; API 5xx / latency alerts ([platform-incident.md](platform-incident.md)); Query Insights.
- **Topology (NF-006, SPEC 9.4):** prd primary `farmerapp-prd` is HA `REGIONAL` (synchronous standby in a second zone of asia-south1), PITR on (7 days of WAL), 30 daily backups stored in **asia-south2**; read replica `farmerapp-prd-replica`. stg / dev: zonal, 7 backups, no PITR.

## A. Pressure alerts (CPU, connections, storage, lag)

1. CPU / slow queries: Query Insights (console) top queries by total time; look for a missing index or a runaway batch job:
   ```bash
   gcloud run jobs executions list --region $REGION --project $PROJECT --limit 10
   gcloud run jobs executions cancel <execution> --region $REGION --project $PROJECT   # runaway job
   ```
2. Connections at 80% of `max_connections`: usually Cloud Run scale-out (each instance holds a pool). Cap the api temporarily (`gcloud run services update api --max-instances 15 ...`) and check for leaked sessions:
   ```sql
   SELECT usename, state, count(*) FROM pg_stat_activity GROUP BY 1, 2 ORDER BY 3 DESC;
   ```
3. Storage > 80%: disk autoresize is on; confirm it is growing, and check `location_point` partitions are being purged (`purge-location-points` job, prd `--apply`).
4. Replica lag > 60 s: heavy writes or an analytical query on the replica; lag does not affect the primary. If it keeps growing, stop long queries on the replica.

## B. Zonal failure / primary unhealthy (HA failover)

Cloud SQL fails over to the standby automatically (about a minute). To force it (for a stuck primary, or in the quarterly drill on stg):
```bash
gcloud sql instances failover farmerapp-$ENV --project $PROJECT
gcloud sql operations list --instance farmerapp-$ENV --project $PROJECT --limit 3
```
The private IP does not change; Cloud Run reconnects. Expect a burst of 5xx during the switch.

## C. Point-in-time restore (bad migration, bad batch, accidental delete) — RPO minutes

Never restore over the live instance. Clone to a new instance at a time just before the damage, verify, then either copy the damaged rows back or switch the app to the clone.
```bash
T='2026-12-20T04:15:00Z'   # UTC, just before the incident (audit log / job logs give it)
gcloud sql instances clone farmerapp-$ENV farmerapp-$ENV-pitr-$(date -u +%Y%m%d%H%M) \
  --point-in-time "$T" --project $PROJECT
```
- Row-level repair (preferred): connect to the clone as the owner, export the affected tenant's rows (`\copy (SELECT ... WHERE tenant_id = ...) TO ...`) and re-insert in a reviewed transaction on the primary.
- Whole-instance switch (only if the primary is unusable):
  1. Stop writers. Close the public path (the LB gets 404/403 from Cloud Run; devices queue in their outbox) and pause the schedulers; Pub/Sub keeps messages for 7 days:
     ```bash
     gcloud run services update api --region $REGION --project $PROJECT --ingress internal
     for j in $(gcloud scheduler jobs list --location $REGION --project $PROJECT --format='value(ID)'); do
       gcloud scheduler jobs pause "$j" --location $REGION --project $PROJECT; done
     ```
  2. Point api / worker / jobs at the clone: `gcloud run services update api --region $REGION --project $PROJECT --update-env-vars DB_INSTANCE_CONNECTION_NAME=<project>:<region>:<clone>` (same for `worker`, the `migrate` job and every other job with `gcloud run jobs update <job> --update-env-vars ...`; the Cloud SQL connector reaches the clone over its private IP with IAM auth, docs/deploy/configuration.md; the IAM database users must exist on the clone), then make it permanent in Terraform (import the clone as `module.sql`, human apply).
  3. Re-grant the Postgres roles on the clone (`GRANT farmerapp_app TO ...`, statements in `infra/modules/sql/main.tf`).
  4. Reopen: `gcloud run services update api --ingress internal-and-cloud-load-balancing ...` and `gcloud scheduler jobs resume ...`.
- Human approval (platform lead + product owner) before any whole-instance switch in prd.

## D. Restore a backup (no PITR in dev / stg, or older than 7 days)

```bash
gcloud sql backups list --instance farmerapp-$ENV --project $PROJECT --limit 10
gcloud sql instances create farmerapp-$ENV-restore --project $PROJECT --region $REGION \
  --database-version POSTGRES_16 --tier db-custom-2-7680 --no-assign-ip \
  --network projects/$PROJECT/global/networks/farmerapp-$ENV
gcloud sql backups restore <BACKUP_ID> --backup-instance farmerapp-$ENV \
  --restore-instance farmerapp-$ENV-restore --project $PROJECT
```
Region loss: see [disaster-recovery.md](disaster-recovery.md) (backups are already stored in asia-south2).

## Verification

- `gcloud sql instances describe farmerapp-$ENV --format='value(state,gceZone,secondaryGceZone)'` shows `RUNNABLE`.
- API `/v1/health` green, 5xx back to baseline, OPS-003 alerts closed.
- After a restore: row counts per tenant for the affected tables match the expectation written in the ticket; `alembic current` equals the deployed head.

## Communication

- Sev 1: `#farmerapp-ops` every 15 min; product owner informed before any restore that loses writes (RPO); cluster heads told that devices keep their outbox and re-sync (NF-002), so field data written offline is not lost.

## Follow-up

- Delete clones / restore instances after the postmortem (human, with deletion protection turned off explicitly).
- Postmortem for Sev 1 with the measured RPO / RTO.
