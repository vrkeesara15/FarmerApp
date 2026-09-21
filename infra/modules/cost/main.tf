# OPS-012 (SPEC 12.2) and NF-015 (SPEC 7): where the money goes, and an alarm when it moves.
#
#   main.tf      dataset, the cost-watch service account and the daily scheduled query
#   views.tf     cost by day / service / component / tenant, and the 7-day anomaly view
#   alerts.tf    OPS-012 alert policies (daily anomaly, LLM and SMS per tenant, budget)
#
# What is Terraform and what is a human (docs/runbooks/cost-and-budget.md):
#
#   Terraform  the BigQuery dataset the export lands in, every view over it, the daily
#              anomaly watch, the budget and all the alert policies.
#   Human      enabling the Cloud Billing export itself and creating the budget's billing
#              account binding: both live on the *billing account*, which is outside every
#              project and needs a billing admin. Once the export exists, set
#              `billing_export_table` (and `billing_account`) in the env tfvars.
#
# Tenant attribution (the "cost by tenant" half of SPEC 12.4), stated plainly because the
# honest answer is "partly measured, partly apportioned":
#
#   direct       nothing. FarmerApp is one multi-tenant deployment: api, worker, console,
#                embed, Cloud SQL and the buckets all serve every tenant, and the Cloud Run
#                *jobs* take `--tenant-id` arguments rather than running one job per tenant.
#                No GCP resource is therefore billable to a single tenant, and a label on a
#                shared service can only say *what* it is, not *whose* it is.
#   labels       every Cloud Run service and job carries `app`, `env`, `component` and
#                `tenancy` (modules/run_service, modules/run_job). `component` gives cost by
#                service without guessing from SKU names, and `tenancy = shared | dedicated`
#                marks anything that ever becomes single-tenant, so the split below keeps
#                working when a large tenant gets its own service.
#   apportioned  shared cost is split across tenants by their share of the day's billable
#                activity (visits + order lines) from the dbt marts. It is a fair-use split,
#                not a measurement: see the limits in views.tf and docs/cost-model.md.
#   metered      LLM and SMS *are* per tenant, from the API's own log lines (`llm_call` and
#                `otp_sent` both carry `tenant_id`). They are not in the billing export at
#                all -- different vendors -- so they are metered in Cloud Monitoring and
#                priced with the rate card in variables.tf. NF-015 excludes them from the
#                infrastructure budget; OPS-012 still alerts on them per tenant (alerts.tf).

locals {
  export_ready = var.billing_export_table != ""
  tenant_ready = local.export_ready && var.marts_dataset != ""
  export_ref   = "`${var.project_id}.${var.dataset_id}.${var.billing_export_table}`"
  watch_table  = "`${var.project_id}.${var.dataset_id}.cost_watch_daily`"
  labels       = { app = "farmerapp", env = var.env }
}

resource "google_bigquery_dataset" "cost" {
  project     = var.project_id
  dataset_id  = var.dataset_id
  location    = var.region
  description = "OPS-012 / NF-015: Cloud Billing export and the cost views for ${var.env}."
  labels      = local.labels

  # Billing data is business data, not personal data, but it stays in region with everything
  # else (NF-011) and is never deleted by Terraform.
  delete_contents_on_destroy = false
}

# --- the daily cost watch ----------------------------------------------------------------
# A BigQuery scheduled query, not a Cloud Run job: the computation is one SQL statement over
# a BigQuery table, and a job would need an image, a service account and a scheduler for the
# same result. It writes one row per day per check into `cost_watch_daily` (the audit trail
# the runbook reads) and then RAISEs when any of those rows is a breach, so the transfer run
# fails. `transfer_config/completed_transfer_run_count{run_status="FAILED"}` is the metric
# the OPS-012 alert watches (alerts.tf).
#
# The trade: a genuine query error looks the same as a breach. That is deliberate -- both
# mean "the cost watch did not come back clean, go and look" -- and the runbook's first step
# is the table, which says which check fired.

resource "google_service_account" "cost_watch" {
  count = local.export_ready ? 1 : 0

  project      = var.project_id
  account_id   = "farmerapp-cost-watch"
  display_name = "FarmerApp ${var.env} daily cost watch (OPS-012)"
  description  = "Runs the daily BigQuery cost anomaly query. Reads the billing export, writes cost_watch_daily."
}

resource "google_bigquery_dataset_iam_member" "cost_watch_editor" {
  count = local.export_ready ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.cost.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.cost_watch[0].email}"
}

resource "google_project_iam_member" "cost_watch_job_user" {
  count = local.export_ready ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.cost_watch[0].email}"
}

resource "google_bigquery_data_transfer_config" "cost_watch" {
  count = local.export_ready ? 1 : 0

  project              = var.project_id
  location             = var.region
  display_name         = "farmerapp-${var.env}-cost-watch"
  data_source_id       = "scheduled_query"
  schedule             = var.cost_watch_schedule
  service_account_name = google_service_account.cost_watch[0].email

  params = {
    query = <<-SQL
      -- OPS-012: yesterday's net spend against the trailing 7-day average.
      -- One row per check per day in cost_watch_daily; RAISE on any breach so the
      -- transfer run fails and the alert policy fires.
      DECLARE breaches INT64;

      CREATE TABLE IF NOT EXISTS ${local.watch_table} (
        checked_at TIMESTAMP,
        day        DATE,
        scope      STRING,
        name       STRING,
        currency   STRING,
        net_cost   FLOAT64,
        avg_7d     FLOAT64,
        ratio      FLOAT64,
        threshold  FLOAT64,
        breach     BOOL
      )
      PARTITION BY day
      OPTIONS (description = 'OPS-012 daily cost watch results (see infra/modules/cost).');

      DELETE FROM ${local.watch_table}
      WHERE day >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 3 DAY);

      INSERT INTO ${local.watch_table}
      SELECT
        CURRENT_TIMESTAMP(),
        day,
        'total',
        'all services',
        currency,
        net_cost,
        avg_7d,
        ratio,
        ${var.daily_spend_ratio},
        ratio > ${var.daily_spend_ratio}
      FROM `${var.project_id}.${var.dataset_id}.v_cost_anomaly_daily`
      WHERE day >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 3 DAY)
        AND avg_7d IS NOT NULL;

      SET breaches = (
        SELECT COUNT(*) FROM ${local.watch_table}
        WHERE breach AND day >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 3 DAY)
      );

      IF breaches > 0 THEN
        RAISE USING MESSAGE = FORMAT(
          'OPS-012: %d day(s) above %.0f%% of the trailing 7-day average. See %s.',
          breaches, ${var.daily_spend_ratio} * 100, '${var.dataset_id}.cost_watch_daily');
      END IF;
    SQL
  }

  depends_on = [
    google_bigquery_dataset_iam_member.cost_watch_editor,
    google_project_iam_member.cost_watch_job_user,
    google_bigquery_table.views,
  ]
}

# --- NF-015 budget -----------------------------------------------------------------------
# The absolute guard rail: "pilot infra under Rs 25,000/month, at 50 stores under
# Rs 1,00,000/month". The anomaly watch above catches a sudden jump; this catches a slow
# climb that never looks anomalous day to day.

resource "google_pubsub_topic" "budget" {
  project = var.project_id
  name    = var.budget_topic
  labels  = local.labels
}

resource "google_billing_budget" "monthly" {
  count = var.billing_account != "" && var.monthly_budget_inr > 0 ? 1 : 0

  billing_account = var.billing_account
  display_name    = "FarmerApp ${var.env} monthly infrastructure budget"

  budget_filter {
    projects               = ["projects/${var.project_id}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "INR"
      units         = tostring(var.monthly_budget_inr)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.budget_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  # Forecast rules give the owner a week's warning instead of a post-mortem.
  dynamic "threshold_rules" {
    for_each = [for t in var.budget_thresholds : t if t >= 1.0]
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "FORECASTED_SPEND"
    }
  }

  all_updates_rule {
    pubsub_topic                   = google_pubsub_topic.budget.id
    schema_version                 = "1.0"
    disable_default_iam_recipients = false
  }
}
