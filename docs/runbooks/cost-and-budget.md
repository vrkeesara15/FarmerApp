# Runbook: cost anomaly and budget (OPS-012 / NF-015)

- **Owner:** product owner (the budget) + platform lead (the cause)
- **Severity:** Sev 2 — a ticket, next business hour. Nothing here is an outage, and paging
  someone at 03:00 about a bill teaches them to ignore pages.
- **Detection:**
  - `[env] daily spend above 130% of the 7-day average` — the daily BigQuery cost watch
    (`infra/modules/cost`) failed its run, which means either a breach or a broken query.
  - `[env] LLM spend above ₹500/day for one tenant`, `[env] SMS spend above ₹500/day for one
    tenant` — log-based metrics (`farmerapp_llm_input_tokens`, `farmerapp_otp_sent`) past the
    rate-card equivalent in a 6-hour window.
  - `[env] monthly budget threshold crossed` — the Cloud Billing budget at 50 / 90 / 100 /
    130%, actual or forecast.

The model these numbers are judged against — what each resource should cost at 5 stores and at
50, and the ordered list of levers — is [docs/cost-model.md](../cost-model.md).

## Daily spend anomaly

1. **Read the watch table first.** It says whether the alert is a breach or a broken query:

   ```sql
   SELECT * FROM `farmerapp-prd.farmerapp_cost.cost_watch_daily`
   ORDER BY checked_at DESC LIMIT 20;
   ```

   A row with `breach = true` names the day and the ratio. No rows, or a row from days ago,
   means the scheduled query itself failed — open the transfer run in BigQuery > Scheduled
   queries and read its error.

2. **Find the service that moved.**

   ```sql
   SELECT day, service, component, ROUND(net_cost, 2) AS inr
   FROM `farmerapp-prd.farmerapp_cost.v_cost_daily_by_service`
   WHERE day >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 10 DAY)
   ORDER BY day DESC, inr DESC;
   ```

   Then one level down, to the SKU, which is what names the actual knob:

   ```sql
   SELECT day, sku, pricing_unit, ROUND(usage_amount, 2) AS used, ROUND(net_cost, 2) AS inr
   FROM `farmerapp-prd.farmerapp_cost.v_cost_daily_by_sku`
   WHERE day = DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 1 DAY)
   ORDER BY inr DESC LIMIT 20;
   ```

3. **Classify it.** In practice it is almost always one of four:

   | Signature | Cause | What to do |
   |---|---|---|
   | Cloud Run instance time up, requests flat | `min_instances` left high after a load test, or a revision that never scales down | Check `min_instances` in the env tfvars against what is deployed |
   | Datastream + BigQuery both up, one day only | a stream backfill (a table added to the allowlist) | Expected; note it on the ticket and close |
   | Logging ingest up after a deploy | `LOG_LEVEL=DEBUG` shipped, or a loop logging per row | Roll the setting back; check the log-based metric volume |
   | BigQuery scanned bytes up | a query without a partition filter, usually a new dashboard | Find it in `INFORMATION_SCHEMA.JOBS_BY_PROJECT`, add the filter |

4. **Close the loop.** A legitimate jump (a backfill, a load test, a new environment) is closed
   with a note on the ticket. A jump nobody ordered is a runaway: fix the cause, then check
   the next morning's watch is clean.

## LLM spend for one tenant

The LLM is the *fallback* path of the diagnosis pipeline, so high spend is a symptom of the
corpus not answering, not of the model being expensive.

1. Check the OPS-009 LLM-fallback-rate alert. If the fallback rate jumped too, fix that cause
   (corpus gap, encoder regression — see
   [observability.md](observability.md#ops-009-diagnosis-review-queue-and-llm-fallback))
   rather than the bill.
2. If the rate is normal and the volume simply grew, that is a product conversation, not an
   incident: at 50 stores a point of fallback rate is about ₹6,000/month
   ([cost-model.md](../cost-model.md)), so approving corpus images for the crops and districts
   that fall through (WC-007) is the cheapest fix there is.
3. **Emergency brake:** `diagnosis_llm = "off"` (Terraform; `DIAGNOSIS_LLM=off` on api, worker
   and jobs) sends every fallback straight to the agronomist review queue. Spend stops
   immediately, the queue grows, and OPS-009 starts firing instead. It is a stop-gap.

## SMS spend for one tenant

1. Compare sends against verifications: `farmerapp_otp_sent{channel="sms"}` vs
   `farmerapp_otp_delivered` and actual logins. Sends without logins are either SMS pumping
   (which pages under OPS-013 at a much higher rate — see
   [suspected-data-breach.md](suspected-data-breach.md) only if it comes with other signals)
   or a client retrying.
2. Below the paging threshold the causes are dull: a campaign, a re-onboarding drive, or an app
   version retrying OTP sends. Check `app_version` on the requests before blaming the tenant.
3. Levers: tighten the per-phone and per-IP OTP rate limits (tenant settings), or switch
   OTP to WhatsApp-first for that tenant ([otp-provider-outage.md](otp-provider-outage.md)).

## Monthly budget threshold

1. Where the month stands:

   ```sql
   SELECT * FROM `farmerapp-prd.farmerapp_cost.v_cost_monthly_vs_budget`
   ORDER BY invoice_month DESC LIMIT 3;
   ```

2. A **forecast** threshold at 100% is the useful one: it arrives with days left to act. Work
   the lever table in [cost-model.md](../cost-model.md) from the top — it is ordered cheapest
   first, and the last two (drop the read replica, HA off) trade availability for money and are
   a decision with the product owner, not a midnight change.

3. If the budget is simply wrong because the pilot grew, raise `monthly_budget_inr` in the env
   tfvars with a note saying what changed. A budget nobody believes is worse than none.

## Human gates (once per environment)

Both live on the **billing account**, not in any project, so they need a billing admin and
neither can be done by Terraform or by Claude.

1. **Cloud Billing export to BigQuery.** Billing → Billing export → BigQuery export → *Detailed
   usage cost*, destination project `farmerapp-<env>`, dataset `farmerapp_cost` (Terraform has
   already created it). Data starts arriving within a day; the table is named
   `gcp_billing_export_resource_v1_<billing account id with underscores>`.
   Then set it in the env tfvars and apply:

   ```hcl
   billing_export_table = "gcp_billing_export_resource_v1_0123AB_4567CD_89EF01"
   ```

   That one variable creates the views, the daily cost watch and its alert.

2. **Budget.** Set `billing_account = "0123AB-4567CD-89EF01"` in the same tfvars. Terraform
   then creates the NF-015 budget with the 50 / 90 / 100 / 130% thresholds and their forecast
   twins, publishing to the `cost.budget` topic that the alert policy watches.

Until both are set, the cost dataset exists and is empty, the BigQuery-backed alerts do not
exist, and the LLM and SMS per-tenant alerts work anyway — they read log-based metrics, not
the bill.

## Verification

- The morning after a fix: `cost_watch_daily` has a fresh row for yesterday with
  `breach = false`.
- The cost dashboard (`FarmerApp <env> cost`) shows the driver back at its usual level.
- The monthly view's `budget_share` is trending to land under 1.0.
