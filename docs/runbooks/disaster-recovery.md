# Runbook: disaster recovery (NF-006) and quarterly restore drill

- **Owner:** platform lead
- **Severity:** Sev 1
- **Detection:** asia-south1 regional outage (Google Cloud status), primary and standby both unavailable, unrecoverable corruption, or the quarterly drill (SPEC 11.4).

## Objectives (NF-006)

| Objective | Target | How it is met |
|---|---|---|
| Availability | API 99.5% monthly (pilot), 99.9% (SaaS) | Cloud Run min 1 instance for api / console in prd, Cloud SQL HA `REGIONAL`, SLO + burn-rate alerts (`infra/modules/monitoring/slo.tf`) |
| RPO | 15 min | PITR (WAL retained 7 days) inside the region: seconds. Region loss: last automated backup, stored in **asia-south2** (daily); devices keep unsynced work in their outbox (NF-002) and re-send it, which closes most of the gap for field data |
| RTO | 4 h | Zonal failure: automatic HA failover (~1 min). Region loss: restore the backup into asia-south2 and bring the stack up there with Terraform (steps below, rehearsed quarterly) |

Known gap: a region loss between two daily backups can lose server-only writes of up to 24 h
(webhooks, console edits). Closing it to 15 min needs a cross-region read replica in
asia-south2 (promotable) — a cost decision for SaaS, tracked in the NF-006 notes.

## Region loss procedure (prd, asia-south1 unavailable)

Decision to invoke: platform lead + product owner, after 30 min of regional outage with no ETA.

1. Freeze: announce in `#farmerapp-ops`; field apps keep capturing offline.
2. Restore the database in asia-south2 from the cross-region backup:
   ```bash
   PROJECT=farmerapp-prd
   gcloud sql backups list --instance farmerapp-prd --project $PROJECT --limit 5   # newest SUCCESSFUL, location asia-south2
   gcloud compute addresses create farmerapp-prd-dr-psa --global --purpose VPC_PEERING \
     --prefix-length 20 --network farmerapp-prd --project $PROJECT                  # if the PSA range needs room
   gcloud sql instances create farmerapp-prd-dr --project $PROJECT --region asia-south2 \
     --database-version POSTGRES_16 --tier db-custom-2-7680 --availability-type REGIONAL \
     --no-assign-ip --network projects/$PROJECT/global/networks/farmerapp-prd \
     --database-flags cloudsql.iam_authentication=on,cloudsql.logical_decoding=on
   gcloud sql backups restore <BACKUP_ID> --backup-instance farmerapp-prd \
     --restore-instance farmerapp-prd-dr --project $PROJECT
   ```
3. Bring up compute in asia-south2 (human `terraform apply`, prd is never applied from CI): in a DR copy of `infra/envs/prd` set `region = "asia-south2"`, `sql_backup_location = null`, import the restored instance as `module.sql.google_sql_database_instance.main`, apply. Cloud Run images come from Artifact Registry (asia-south1 multi-region pull may be down: keep a copy with `gcloud artifacts docker images copy` into an asia-south2 repository as part of the drill).
4. Re-grant Postgres roles on the restored instance, run `migrate`, update the LB backends (serverless NEGs in asia-south2) — the global LB, IP and certificate survive a regional outage.
5. Payments: run `reconcile-payments` for the outage days; Razorpay re-sends webhooks for 24 h.
6. Verify (below), then reopen and communicate.

## Verification

- `/v1/health` green through the LB; login + sync + order on a pilot device.
- Row counts per tenant for farmer, visit, order, payment vs the last known figures (owner home, WC-001) — record the measured RPO.
- Time from invocation to reopening recorded as the measured RTO.

## Quarterly drill checklist (SPEC 11.4 "restore drill from backup")

Run on **stg** (never restore over prd). Record results in `docs/postmortems/drills/YYYY-Qn.md`.

- [ ] Pick the newest automated backup of `farmerapp-stg`; note its time (RPO baseline).
- [ ] Restore it into a new instance (`gcloud sql instances create ... && gcloud sql backups restore ...` as above), timing each step.
- [ ] PITR clone of `farmerapp-stg` to 1 h ago succeeds (`gcloud sql instances clone ... --point-in-time`), if PITR is enabled for the drill.
- [ ] Forced HA failover on a HA test instance (`gcloud sql instances failover`), API errors during the switch < 2 min.
- [ ] Point a stg api revision at the restored instance (`--update-env-vars DB_INSTANCE_CONNECTION_NAME=<project>:<region>:<restored>`), run `alembic current` via the `migrate` job image, smoke tests pass (`scripts/smoke.sh`).
- [ ] Row counts per tenant match the source at backup time (script in the drill record).
- [ ] Replay one message from a DLQ ([payment-webhook-backlog.md](payment-webhook-backlog.md)).
- [ ] Measured RTO < 4 h and RPO within target; gaps become tickets.
- [ ] Delete the drill instances (human; stg only).
- [ ] Update this runbook with anything that was wrong.

## Communication

- Owners and cluster heads: "field capture continues offline; sync resumes at <time>".
- Customers (SaaS): status page / e-mail per the contract once RTO exceeds 1 h.

## Follow-up

- Postmortem for any real invocation; drill record every quarter.
