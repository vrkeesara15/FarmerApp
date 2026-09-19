# Runbook: bad mobile release rollback

- **Owner:** mobile lead (decision with the product owner)
- **Severity:** Sev 1 if crash-free sessions < 99% on the new version or sync is broken; Sev 2 for a functional regression with a workaround
- **Detection:** Firebase Crashlytics velocity alert / crash-free sessions per app version (OPS-002: target > 99.5%, halt staged rollout below 99%); `SLO: Sync success below 97% for 30 min` concentrated on the new `app_version`; support reports.

Crashlytics and Play Console live outside Terraform. **Human gate (setup, once):** create
the Firebase projects for the agent and farmer apps, enable Crashlytics, add the
`google-services.json` per flavour (not committed; CI secret), and configure a Crashlytics
velocity alert and a "crash-free users < 99% for version X" alert to the on-call e-mail /
Slack. Until then this detection is manual.

## Steps

1. Confirm the regression is version-specific: Crashlytics > Issues filtered by version; for sync, compare API errors by `User-Agent` / app version in the access logs:
   ```bash
   gcloud logging read 'resource.labels.service_name="api" AND jsonPayload.event="request" AND jsonPayload.path="/v1/sync" AND jsonPayload.status>=400' \
     --project $PROJECT --freshness 2h --limit 200 --format='value(jsonPayload.status)' | sort | uniq -c
   ```
2. **Halt the staged rollout** (human, Play Console): Release > Production (or closed track) > Manage release > *Halt rollout*. Users who already updated keep the bad build; nobody new gets it. `mobile-release.yml` only uploads to the internal track; promotion is always manual.
3. Kill switch: if the regression is in a feature behind a server-side flag, turn it off for the tenant(s) (tenant settings, `PATCH /v1/settings`, audited) — no app update needed. A remote-config `min_supported_version` / feature kill switch in the apps is a follow-up (not built yet).
4. Ship the fix: Play does not allow downgrades, so "rollback" means a new build with a higher `versionCode` from the last good commit (tag `agent-vX.Y.Z+1` or `farmer-v...` on the revert), through the internal track, then a fresh staged rollout (10% -> 50% -> 100%, watching crash-free between steps).
5. Data safety: the outbox survives app updates (Drift DB migrations must be forward-only). If the bad build corrupted local data, do **not** ask users to clear storage (that drops unsynced work); ship a repair migration.

## Verification

- Crash-free sessions of the new build > 99.5% over 24 h at 10% rollout before widening.
- Sync success SLO back above 99%; no `sync_op_integrity_error` spike for the version.

## Communication

- Ops lead to cluster heads (WhatsApp): which version is affected, "do not uninstall; update when the new version arrives".
- Sev 1 postmortem.

## Follow-up

- Add the failing path to the widget / integration tests; add a Crashlytics non-fatal for the case if it was silent.
