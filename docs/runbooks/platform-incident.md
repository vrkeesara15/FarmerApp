# Runbook: platform incident (API / console down, error rate, latency)

- **Owner:** platform lead (on-call)
- **Severity:** Sev 1 when an uptime check fails or the availability SLO burns 14x in 1 h; Sev 2 for error rate (OPS-002), 6x / 6 h burn and latency SLO alerts
- **Detection:** `[env] api down (OPS-001, sev1)`, `[env] console down (OPS-001, sev1)`, `[env] <service> 5xx ratio > 2% (OPS-002, sev2)`, `[env] application error burst (OPS-002, sev2)`, `SLO: API availability burning ...`, `SLO: API read|write p95 > ... ms`
- **Dashboard:** "FarmerApp <env> platform"

## Steps

1. Acknowledge the alert in Cloud Monitoring (Incidents) and post in `#farmerapp-ops`: "Investigating <alert>, next update in 15 min".
2. Is it us or the edge? Check the service directly and through the LB:
   ```bash
   curl -sS -o /dev/null -w '%{http_code} %{time_total}s\n' https://api.farmerapp.in/v1/health
   gcloud run services describe api --region $REGION --project $PROJECT \
     --format='value(status.latestReadyRevisionName,status.traffic)'
   gcloud compute ssl-certificates describe farmerapp-$ENV-cert --global --project $PROJECT \
     --format='value(managed.status,managed.domainStatus)'
   ```
   Certificate not `ACTIVE`, or 403 / 429 from the LB: check Cloud Armor (step 6).
3. Recent deploy? Compare the failing revision with the previous one and roll back traffic:
   ```bash
   gcloud run revisions list --service api --region $REGION --project $PROJECT --limit 5
   gcloud run services update-traffic api --region $REGION --project $PROJECT \
     --to-revisions <previous-revision>=100
   ```
   Same for `console` / `worker`. A migration that is not backward compatible is a Sev 1: do not roll the schema back by hand, page the platform lead ([cloud-sql-failover-restore.md](cloud-sql-failover-restore.md)).
4. Errors: open Error Reporting for the top new group, and the logs:
   ```bash
   gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="api" AND (jsonPayload.level="error" OR severity>=ERROR)' \
     --project $PROJECT --freshness 30m --limit 50 --format json | jq -r '.[].jsonPayload | [.timestamp,.event,.path,.trace_id] | @tsv'
   ```
5. Latency: Cloud SQL first (CPU, connections, Query Insights top queries), then instance count at `max_instances` (dashboard "Instances by service"). Temporary relief:
   ```bash
   gcloud run services update api --region $REGION --project $PROJECT --max-instances 30
   ```
   (Terraform will revert it on the next apply: record the change in the incident ticket.)
6. Cloud Armor blocking legitimate traffic (prd enforce):
   ```bash
   gcloud logging read 'resource.type="http_load_balancer" AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"' \
     --project $PROJECT --freshness 30m --limit 50 --format='value(jsonPayload.enforcedSecurityPolicy.name,jsonPayload.enforcedSecurityPolicy.priority,httpRequest.requestUrl)'
   # emergency: put one rule into preview (log only)
   gcloud compute security-policies rules update <priority> --security-policy farmerapp-$ENV-armor \
     --project $PROJECT --preview
   ```
   Put the rule back to enforce (and fix the path regex in `infra/modules/lb`) within the day.

## Verification

- All three uptime checks green from every region for 10 minutes.
- 5xx ratio below 1% and p95 back under 300 ms (reads) / 600 ms (writes) on the platform dashboard.
- The alert auto-closes (Incidents view).

## Communication

- `#farmerapp-ops` every 15 minutes during Sev 1 until resolved.
- If field officers are affected for more than 30 minutes: the ops lead messages cluster heads (WhatsApp group) that capture keeps working offline and will sync later (NF-002).

## Follow-up

- Sev 1: blameless postmortem in `docs/postmortems/YYYY-MM-DD-<slug>.md` within 5 working days.
- Any manual change (traffic split, max instances, Armor preview) is reconciled in Terraform or reverted.
