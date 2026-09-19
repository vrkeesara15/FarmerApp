# Pilot go-live checklist (M5 definition of done)

Target: 5 FCC stores live, December 2026. Every item below is a human action; the code and
infrastructure for each is on `main`. Sign each line with a name and date.

## 1. Accounts and repository
- [ ] GitHub repository created; `main` pushed; branch protection (required checks, linear history, signed commits); secret scanning with push protection on (SEC-001).
- [ ] CODEOWNERS teams `@farmerapp/platform` and `@farmerapp/security` created with real members.
- [ ] Actions variables set: `WIF_PROVIDER`, `BUILD_SA`, `DEPLOY_SA_DEV`, `DEPLOY_SA_STG`, `DEPLOY_SA_PRD`; GitHub environments `dev`, `staging`, `production` with required reviewers.

## 2. Google Cloud
- [ ] Projects `farmerapp-ops`, `-dev`, `-stg`, `-prd` created with billing (asia-south1).
- [ ] `infra/bootstrap` applied by an org admin (state bucket, Artifact Registry, WIF, deployer SAs, org policies SEC-018).
- [ ] `infra/envs/dev` applied once; stg and prd applied after review (never from the loop).
- [ ] Security Command Center enabled at the org and `org_id` set (SEC-019).
- [ ] Cloud KMS key ring and key in asia-south1 for PII (SEC-026); `pii-hash-pepper` secret created.
- [ ] Secret values added: JWT signing key, OTP provider credentials, Razorpay key id/secret/webhook secret, LLM key (M6).
- [ ] Notification channels (Slack/PagerDuty/phone) created and wired to alert policies; on-call rota for sowing season.
- [ ] Cloud Trace agent role granted to service accounts; billing export for the cost dashboard.
- [ ] Cloud Armor bot management: reCAPTCHA Enterprise keys (SEC-014).
- [ ] `job_tenant_ids` set for stg and prd so scheduled jobs run per tenant.

## 3. Data and migrations
- [ ] `alembic upgrade head` run by the migrate job in each environment.
- [ ] `backfill-pii-encryption` run per tenant after migration 0024–0026; verify counts; schedule the contract step (drop plain columns) only after a full release cycle.
- [ ] `backfill-farm-photo-phash` run per tenant.
- [ ] FCC tenant created with real stores, clusters, villages, users; demo seed never run in stg/prd.
- [ ] Product master replaced with FCC's real SKUs; CIB&RC label claims entered and approved by the agronomist (human gate, SPEC 14.6).
- [ ] Seller GSTINs and invoice series per store set.

## 4. Providers
- [ ] SMS provider with DLT-registered templates (OTP, visit confirmation, payment links); WhatsApp fallback templates approved.
- [ ] Razorpay account in test mode verified end to end on stg, then live keys in prd.
- [ ] Accountant validates a GST invoice PDF and the day-close report.

## 5. Mobile
- [ ] Real certificate pins (primary and backup key) for the stg and prd API domains; API certificates issued with a stable key.
- [ ] Play Integrity: Cloud project linked in Play Console, API enabled, `PLAY_INTEGRITY_MODE=google` on the API.
- [ ] Release signing keys in Secret Manager; MobSF scan clean (SEC-008).
- [ ] Play Console: background-location declaration, demo video and privacy policy submitted (VV-009); agent app on managed/private distribution.
- [ ] Reference devices (Samsung A-series, Redmi, low-end Realme/Itel): SQLCipher migration, cold start < 3 s, 8-hour duty battery < 6% (VV-001), 72-hour airplane-mode test (NF-002).

## 6. People and legal
- [ ] Employee location policy text final and signed in HR onboarding; in-app version matches (VV-010, FA-011).
- [ ] Farmer consent text reviewed by legal (DPDP) in all five languages.
- [ ] Native-speaker review of Telugu, Kannada, Hindi and Marathi strings (NF-008).
- [ ] Field officers trained; store managers trained on store mode and day close.

## 7. Operations
- [ ] Restore drill on stg from backup (NF-006) with timings recorded.
- [ ] Cloud Run load test in stg against NF-005 budgets; decision recorded on the sync batch latency objective.
- [ ] External penetration test (API, console, both apps) and fixes (SPEC 11.4).
- [ ] Runbooks reviewed by the on-call owners.

## Sign-off
| Role | Name | Date |
|---|---|---|
| Owner / director | | |
| Platform lead | | |
| Security | | |
| Operations (cluster head) | | |
