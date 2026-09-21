# Cost model (NF-015)

> NF-015: *pilot infra (5 stores) under ₹25,000/month; at 50 stores under ₹1,00,000/month,
> excluding SMS and LLM; cost dashboard per tenant.*

This is the planning model behind that requirement: every resource the platform runs, what it
should cost at each scale, and what to turn when a number goes the wrong way. SPEC 7 already
says the figures are estimates — this document makes the *assumptions* explicit so the
estimate can be argued with, and names the levers so a breach has an answer rather than a
meeting.

The measured figures live next to it: `infra/modules/cost` builds the BigQuery views over the
Cloud Billing export (`v_cost_daily_by_service`, `v_cost_daily_by_sku`,
`v_cost_daily_by_tenant`, `v_cost_monthly_vs_budget`), the Cloud Monitoring **cost** dashboard
carries the usage drivers, and OPS-012 alerts when a day jumps or a month drifts. When the
model and the bill disagree, the bill is right and this file gets corrected.

## Assumptions

| | Value | Why |
|---|---|---|
| Region | `asia-south1` (Mumbai) | NF-011 data residency |
| Exchange rate | **₹88 / USD** | GCP bills in USD for an INR billing account at the month's rate |
| Pricing date | September 2026 list prices, no committed-use discount unless a row says so | CUDs are a decision, not a default |
| Hours | 730 per month | |
| **Pilot (5 stores)** | 25 officers, 5 store tablets, ~10,000 farmers, ~200 visits/day, ~150 orders/day, ~6,000 diagnoses/month, ~300k API requests/month | SPEC 1 pilot shape |
| **50 stores** | 250 officers, ~100,000 farmers, ~2,000 visits/day, ~1,500 orders/day, ~60,000 diagnoses/month, ~3M API requests/month | Linear in stores; NF-007 says the architecture holds to this |
| Photos | 2 per visit at 200 KB (NF-004), kept 3 years then archived (NF-012) | |
| Excluded from the budget | SMS and LLM (NF-015 says so). Modelled separately below, because they are the largest line at scale and somebody has to own them. | |

One environment is budgeted here: **prd**. `dev` and `stg` are separate projects with their
own (much smaller) budgets in their tfvars — ₹5,000 and ₹8,000 — and they are not part of the
NF-015 figure.

## Pilot, 5 stores

The first column is the shape SPEC 9.2 prescribes for `prd`. The second is what the pilot
should actually run, and the difference is the whole point of this section.

| Resource | SPEC 9.2 `prd` shape | ₹/month | Pilot shape | ₹/month |
|---|---|---:|---|---:|
| Cloud SQL primary | `db-custom-2-7680`, **HA regional** | 24,800 | `db-custom-2-7680`, **zonal**, PITR + 30-day backups | 12,400 |
| Cloud SQL read replica | yes | 12,400 | **no** | 0 |
| Cloud SQL storage + backups | 100 GB SSD + backups | 1,500 | same | 1,500 |
| Cloud Run `api` | min 1 instance, 1 vCPU / 512 MiB, always-allocated CPU | 4,400 | same | 4,400 |
| Cloud Run `console` | min 1 instance | 4,400 | **min 0** | 300 |
| Cloud Run `worker`, `embed`, jobs | min 0, request-driven | 1,050 | same | 1,050 |
| HTTPS load balancer | 1 forwarding rule + data processing | 1,760 | same | 1,760 |
| Cloud Armor | policy + ~8 rules, enforcing | 970 | same | 970 |
| Cloud Storage (photos) | ~30 GB by month 12, Standard | 200 | same | 200 |
| Datastream → BigQuery | ~2 GB CDC/month | 100 | same | 100 |
| BigQuery | storage + on-demand dbt queries | 150 | same | 150 |
| Logging, Trace, Monitoring | within free tiers at this volume | 300 | same | 300 |
| Secret Manager, Pub/Sub, Scheduler, Artifact Registry | | 400 | same | 400 |
| **Total (excl. SMS and LLM)** | | **~₹52,400** | | **~₹23,500** |
| **NF-015 budget** | | ₹25,000 | | ₹25,000 |
| | | 🔴 **over by 2.1×** | | 🟢 **6% under** |

### The finding

**Running the pilot on the SPEC 9.2 `prd` shape breaches NF-015 on Cloud SQL alone.** HA
regional doubles the instance price and the read replica adds a third copy: ₹37,200 of a
₹25,000 budget before a single request is served.

That is not a contradiction in the SPEC so much as two requirements written for different
moments. NF-006 asks for **99.5% monthly in the pilot** and 99.9% at SaaS launch. 99.5% is
3.6 hours of downtime a month; a zonal Cloud SQL instance with automated backups and PITR
meets it, and meets RPO 15 min / RTO 4 h, because a zone failure is recovered by restore
(docs/runbooks/cloud-sql-failover-restore.md), not by failover. Regional HA is what 99.9%
needs, and 99.9% is what SaaS launch needs.

**Decision for the pilot** (`infra/envs/prd/terraform.tfvars`, human apply):

1. `sql_tier = "db-custom-2-7680"`, **HA off** until SaaS launch or the first availability
   incident that a failover would have prevented.
2. `sql_read_replica = false`. The replica exists for console analytics; from M7 the console
   reads the BigQuery authorised views (AN-013), so the replica is paying twice for the same
   answer.
3. `min_instances = { api = 1, console = 0, worker = 0, embed = 0 }`. A 2-second cold start on
   a manager's laptop is not the same problem as a 2-second cold start on a farmer's phone:
   NF-005's budget is about the app, and the API keeps its warm instance.

With those three, the pilot lands at **~₹23,500**, about 6% under budget — thin enough that
the OPS-012 daily alert matters.

## 50 stores

| Resource | Shape | ₹/month | Note |
|---|---|---:|---|
| Cloud SQL primary | `db-custom-4-15360`, HA regional | 49,600 | HA is justified here: 99.9%, and an outage now costs 50 stores a trading day |
| Cloud SQL, with 1-year CUD | −25% | −12,400 | The decision to commit; the workload is steady by then |
| Cloud SQL read replica | **no** — console reads BigQuery | 0 | Re-add (₹24,800) only if a report genuinely needs row-level freshness |
| Cloud SQL storage + backups | 500 GB SSD + backups | 7,500 | |
| Cloud Run `api` | min 2, 1 vCPU / 512 MiB | 8,800 | |
| Cloud Run `console` | min 1 | 4,400 | Worth warming at this staff count |
| Cloud Run request-driven | api burst, worker, embed, jobs | 10,500 | |
| HTTPS load balancer | rule + ~200 GB processed | 1,900 | |
| Cloud Armor | policy + rules, enforcing | 1,100 | |
| Cloud Storage (photos) | ~290 GB by month 12, Standard → Nearline at 3 years | 2,000 | NF-012 lifecycle already in `modules/storage` |
| Datastream → BigQuery | ~20 GB CDC/month | 620 | |
| BigQuery | ~200 GB storage + ~2 TB scanned/month | 1,500 | Partition filters are what keep this flat |
| Logging, Trace, Monitoring | ~5 GB ingest, sampled traces | 1,200 | |
| Secret Manager, Pub/Sub, Scheduler, Artifact Registry | | 800 | |
| **Total (excl. SMS and LLM)** | | **~₹77,500** | |
| **NF-015 budget** | | ₹1,00,000 | |
| | | 🟢 **23% under** | |

**Without the two decisions above it is ₹1,14,700 — over budget.** The CUD is worth ₹12,400/month
and the absent read replica ₹24,800/month; either one alone is the difference between passing
and failing. Neither is a default, so both are written into the tfvars with a comment rather
than left to be rediscovered.

## SMS and LLM — excluded from the budget, but not from the bill

NF-015 excludes these because they scale with farmer behaviour rather than with the platform.
At 50 stores they are **larger than the infrastructure bill**, so they get their own owner
(product), their own per-tenant alerts (OPS-012) and their own rate card
(`infra/modules/cost/variables.tf`).

| | Rate | Pilot | 50 stores |
|---|---|---:|---:|
| OTP SMS | ₹0.18 / message (DLT transactional) | ~20,750 msg → **₹3,700** | ~207,000 msg → **₹37,300** |
| LLM fallback (input) | ₹1.25 / 1k tokens | 9.6M tokens → **₹12,000** | 96M → **₹1,20,000** |
| LLM fallback (output) | ₹6.25 / 1k tokens | 0.6M tokens → **₹3,750** | 6M → **₹37,500** |
| **Total** | | **~₹19,450** | **~₹1,94,800** |

LLM assumes 20% of diagnoses fall through to the LLM (the OPS-009 alert fires above 40%) at
~8,000 input tokens per call, which is the corpus context plus one 1280 px image.

**The cost lever for the LLM is the corpus, not the model.** Every percentage point of
fallback rate is ~₹6,000/month at 50 stores. Approving corpus images for the crops and
districts that fall through (WC-007) is cheaper than any prompt change. The emergency brake is
`diagnosis_llm = "off"`, which routes every fallback to the agronomist queue instead — spend
stops, the queue grows, and OPS-009 starts firing instead of OPS-012.

## Levers, cheapest first

When OPS-012 fires, or the monthly budget crosses a threshold, this is the order to work
through. Each one names where it is changed.

| # | Lever | Saves | Where | Cost of pulling it |
|---|---|---|---|---|
| 1 | Cloud Run `min_instances` back to 0 for `console` | ₹4,400/mo per warm instance | `min_instances` in the env tfvars | A cold start on the first request of the morning |
| 2 | Log exclusions: drop the load-balancer request log to 10% sampling outside an incident | ₹0–3,000/mo | `log_config.sample_rate`, `modules/lb` | OPS-013's Armor spike alert gets coarser; raise it back during an incident |
| 3 | Log retention: `_Default` bucket to 30 days | ₹0–2,000/mo | Cloud Logging bucket retention (the SEC-017 audit bucket's 400 days is fixed by law and is not this) | Less history for a post-mortem |
| 4 | `OTEL_SAMPLE_RATIO` to 0.1 | ₹0–1,500/mo | `otel_sample_ratio` in the env tfvars | One request in ten has a trace; the log `trace_id` is still on all of them |
| 5 | BigQuery: require partition filters; keep dbt incremental | ₹0–10,000/mo | `dbt/models`, dataset settings | A full-table scan needs a deliberate override |
| 6 | Datastream: shrink the table allowlist | ₹0–600/mo | `infra/modules/analytics/replicated_columns.json` | A mart loses a column; AN-014 already keeps this list minimal |
| 7 | Cloud SQL: drop the read replica | ₹12,400–24,800/mo | `sql_read_replica` | Console analytics must come from BigQuery (AN-013) |
| 8 | Cloud SQL: HA off | ₹12,400–24,800/mo | `env = "prd"` HA derivation, `modules/sql` | 99.5% instead of 99.9%: a zone failure becomes a restore, not a failover. **Pilot-only.** |
| 9 | Cloud SQL: 1-year committed use | −25% of the instance | Billing console (human) | A year's commitment |
| 10 | BigQuery slot reservation instead of on-demand | Caps query spend | Billing console (human) | Only worth it above ~₹10,000/month of scans |

Levers 7 and 8 are the only two large enough to fix a real breach, and both trade availability
for money — so both are a decision with the product owner, recorded here, not a change an
engineer makes because an alert fired at midnight.

## Cost by tenant, and what it does not mean

SPEC 12.4 asks for cost "by service and by tenant". By service is a measurement. **By tenant is
an apportionment**, and the difference matters if anyone ever bills a customer from it:

* FarmerApp is one multi-tenant deployment. `api`, `worker`, `console`, `embed`, Cloud SQL and
  the buckets serve every tenant at once, and the Cloud Run jobs take `--tenant-id` arguments
  rather than running one job per tenant. **No GCP resource is billable to a single tenant.**
* Every Cloud Run service and job carries `app`, `env`, `component` and `tenancy` labels
  (`modules/run_service`, `modules/run_job`), so the billing export can be grouped by
  component, and a service that ever becomes single-tenant (`tenancy = dedicated` plus a
  `tenant_id` label) is billed to that tenant directly.
* Everything else is split by the tenant's share of the day's **billable activity** — visits
  plus order lines, from the dbt marts. A tenant that mostly reads pays for a bill it did not
  create; a tenant whose officers upload four times the photos pays the same per visit as one
  whose officers upload none.
* **LLM and SMS are genuinely per tenant** (the API's `llm_call` and `otp_sent` log lines both
  carry `tenant_id`), and they are the two costs that actually scale with one tenant's
  behaviour. They are not in the billing export at all — different vendors — so they are
  metered in Cloud Monitoring and priced with the rate card above.

A per-tenant *invoice* would need per-tenant metering of requests, storage and database time.
That is a product decision (SaaS pricing) with real engineering behind it, and it is not what
this view is.

## Alerts on these numbers (OPS-012)

| Alert | Fires when | Goes to |
|---|---|---|
| `daily spend above 130% of the 7-day average` | the daily BigQuery cost watch finds a breach, or fails | product owner + platform lead (ticket) |
| `LLM spend above ₹500/day for one tenant` | `farmerapp_llm_input_tokens` / `_output_tokens` past the rate-card equivalent in a 6-hour window | product owner + agronomist lead |
| `SMS spend above ₹500/day for one tenant` | `farmerapp_otp_sent{channel="sms"}` past the same | product owner + platform lead |
| `monthly budget threshold crossed` | Cloud Billing budget at 50 / 90 / 100 / 130%, actual or forecast | product owner |

Steps for each are in [docs/runbooks/cost-and-budget.md](runbooks/cost-and-budget.md).

## Human gates

Nothing in this model can be measured until a billing-account admin does two things, because
both live on the billing account rather than in any project:

1. **Enable the Cloud Billing export to BigQuery** (detailed usage cost) into the
   `farmerapp_cost` dataset Terraform already created, then set `billing_export_table` in the
   env tfvars. Until then the cost views and the daily anomaly watch do not exist; the LLM and
   SMS alerts work from day one because they read log-based metrics.
2. **Set `billing_account`** so the NF-015 budget resource can be created.

Both are in [docs/runbooks/cost-and-budget.md](runbooks/cost-and-budget.md) with the exact
steps.
