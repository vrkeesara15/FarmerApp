# Runbook: mass location anomaly (OS update breaking background location)

- **Owner:** mobile lead, with the ops lead for field communication
- **Severity:** Sev 2 (Sev 1 if it blocks duty start / visit proof for most officers)
- **Detection:** spike of OPS-006 `officer_sync_silence` notifications (job `officer-sync-silence`, every 15 min); drop in `location.batch` volume or a backlog on `location.batch.worker` (OPS-004); `SLO: Sync success below 97%`; surge of location-based flags (VA rules on gaps / teleports) after an Android or OEM update; officers-on-duty chart flat while duty sessions exist.

Principle (FA-010): location is collected only on duty; never "fix" this by collecting more or outside duty.

## Steps

1. Size it: which tenants, which devices, since when.
   ```bash
   gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="officer-sync-silence"' \
     --project $PROJECT --freshness 6h --format='value(textPayload)' | grep 'silent='
   gcloud logging read 'resource.labels.service_name="api" AND jsonPayload.event="request" AND jsonPayload.path="/v1/location/batch"' \
     --project $PROJECT --freshness 6h --format='value(jsonPayload.status)' | sort | uniq -c
   ```
   Correlate with device OS / app version (Firebase Analytics / Crashlytics device breakdown) and the Android / OEM release notes.
2. Server side is healthy? If batches arrive but fail (4xx/5xx), it is ours: [platform-incident.md](platform-incident.md). If they do not arrive, it is the device.
3. Protect officers from unfair flags while the cause is open: the product owner decides to pause location-based rules (set `enabled: false` in the affected `rules/*.yaml`, reviewed PR, deploy — the batch job then skips them) and to dismiss the flags raised during the window in bulk from the flag inbox (auditable, with the incident id as the reason). Do not delete flags.
4. Field workaround, sent by the ops lead: exact steps for the affected OS version (battery optimisation exemption for the app, "Allow all the time" location while on duty, OEM auto-start setting). Keep it to the documented FA-010 permissions.
5. App fix: foreground-service / permission change in the agent app, released per [bad-mobile-release-rollback.md](bad-mobile-release-rollback.md) (staged rollout).

## Verification

- Silence notifications back to the pre-incident daily baseline; location batches per officer on duty back to normal.
- Rules re-enabled and a nightly run without a flag spike.

## Communication

- Cluster heads within the hour: "known issue with <OS version>; do the following; your visits are not being flagged for it".
- Owners: which days' location-based scores are affected (scorecards, AN-*).

## Follow-up

- Add the OS version to the device test matrix (NF-001); postmortem if Sev 1.
