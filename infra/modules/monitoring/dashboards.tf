# SPEC 12.4 dashboards: platform, business ops, cost. The mobile dashboard
# (active devices, app versions, crash-free rate, sync backlog) lives in Firebase
# Crashlytics / Analytics, outside Terraform (docs/runbooks/bad-mobile-release-rollback.md).

locals {
  lm = "logging.googleapis.com/user"

  platform_tiles = [
    { title = "Requests / s by service", filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\"", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group = ["resource.label.\"service_name\""] },
    { title = "5xx / s by service", filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" metric.label.\"response_code_class\"=\"5xx\"", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group = ["resource.label.\"service_name\""] },
    { title = "Latency p95 by service (ms)", filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group = ["resource.label.\"service_name\""] },
    { title = "API read / write p95 (ms, SLO 300 / 600)", filter = "metric.type=starts_with(\"${local.lm}/farmerapp_api_\") resource.type=\"cloud_run_revision\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_95", group = ["metric.type"] },
    { title = "Instances by service", filter = "metric.type=\"run.googleapis.com/container/instance_count\" resource.type=\"cloud_run_revision\"", aligner = "ALIGN_MAX", reducer = "REDUCE_SUM", group = ["resource.label.\"service_name\""] },
    { title = "Error-level log lines / 5 min", filter = "metric.type=\"${local.lm}/farmerapp_app_errors\" resource.type=\"cloud_run_revision\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["resource.label.\"service_name\""] },
    { title = "Cloud SQL CPU", filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\"", aligner = "ALIGN_MEAN", reducer = "REDUCE_MAX", group = ["resource.label.\"database_id\""] },
    { title = "Cloud SQL disk utilisation", filter = "metric.type=\"cloudsql.googleapis.com/database/disk/utilization\" resource.type=\"cloudsql_database\"", aligner = "ALIGN_MEAN", reducer = "REDUCE_MAX", group = ["resource.label.\"database_id\""] },
    { title = "Cloud SQL connections (num_backends)", filter = "metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\" resource.type=\"cloudsql_database\"", aligner = "ALIGN_MEAN", reducer = "REDUCE_SUM", group = ["resource.label.\"database_id\""] },
    { title = "Cloud SQL replica lag (s)", filter = "metric.type=\"cloudsql.googleapis.com/database/replication/replica_lag\" resource.type=\"cloudsql_database\"", aligner = "ALIGN_MAX", reducer = "REDUCE_MAX", group = ["resource.label.\"database_id\""] },
    { title = "Pub/Sub oldest unacked age (s)", filter = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" resource.type=\"pubsub_subscription\"", aligner = "ALIGN_MAX", reducer = "REDUCE_MAX", group = ["resource.label.\"subscription_id\""] },
    { title = "Pub/Sub undelivered (incl. DLQ replay)", filter = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" resource.type=\"pubsub_subscription\"", aligner = "ALIGN_MAX", reducer = "REDUCE_SUM", group = ["resource.label.\"subscription_id\""] },
    { title = "Cloud Run job executions by result", filter = "metric.type=\"run.googleapis.com/job/completed_execution_count\" resource.type=\"cloud_run_job\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["resource.label.\"job_name\"", "metric.label.\"result\""] },
    { title = "Sync requests vs 2xx", filter = "metric.type=starts_with(\"${local.lm}/farmerapp_sync_\") resource.type=\"cloud_run_revision\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.type"] },
  ]

  business_tiles = [
    { title = "Officers on duty now (by tenant)", filter = "metric.type=\"${local.lm}/farmerapp_officers_on_duty\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_50", group = ["metric.label.\"tenant_id\""] },
    { title = "Open flags (by tenant)", filter = "metric.type=\"${local.lm}/farmerapp_open_flags\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_PERCENTILE_50", group = ["metric.label.\"tenant_id\""] },
    { title = "Visits created / hour", filter = "metric.type=\"${local.lm}/farmerapp_visits_created\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"tenant_id\""] },
    { title = "Orders created / hour", filter = "metric.type=\"${local.lm}/farmerapp_orders_created\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"tenant_id\""] },
    { title = "Payments captured / hour (by mode)", filter = "metric.type=\"${local.lm}/farmerapp_payments_captured\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"mode\""] },
    { title = "Payment webhooks applied / hour (by status)", filter = "metric.type=\"${local.lm}/farmerapp_webhook_applied\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"status\""] },
    { title = "Flags raised / hour (by rule)", filter = "metric.type=\"${local.lm}/farmerapp_flags_raised\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"rule_id\""] },
    { title = "OTP sent vs delivered vs WhatsApp fallback", filter = "metric.type=starts_with(\"${local.lm}/farmerapp_otp_\")", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.type"] },
  ]

  cost_tiles = [
    { title = "Cloud Run billable instance time (s) by service", filter = "metric.type=\"run.googleapis.com/container/billable_instance_time\" resource.type=\"cloud_run_revision\"", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group = ["resource.label.\"service_name\""] },
    { title = "Cloud Run job billable time (s) by job", filter = "metric.type=\"run.googleapis.com/job/billable_instance_time\" resource.type=\"cloud_run_job\"", aligner = "ALIGN_RATE", reducer = "REDUCE_SUM", group = ["resource.label.\"job_name\""] },
    { title = "Cloud SQL CPU (sizing)", filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\"", aligner = "ALIGN_MEAN", reducer = "REDUCE_MAX", group = ["resource.label.\"database_id\""] },
    { title = "Log volume ingested (bytes) by service", filter = "metric.type=\"logging.googleapis.com/billing/bytes_ingested\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["resource.label.\"service_name\""] },
    { title = "BigQuery bytes scanned (query spend)", filter = "metric.type=\"bigquery.googleapis.com/query/scanned_bytes\" resource.type=\"bigquery_project\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = [] },
    { title = "Storage bytes by bucket (photos dominate)", filter = "metric.type=\"storage.googleapis.com/storage/total_bytes\" resource.type=\"gcs_bucket\"", aligner = "ALIGN_MEAN", reducer = "REDUCE_MEAN", group = ["resource.label.\"bucket_name\""] },
    # --- OPS-012: the two vendors that are not on the GCP bill, per tenant ---
    { title = "SMS OTP sends by tenant (SMS spend)", filter = "metric.type=\"${local.lm}/farmerapp_otp_sent\" metric.label.\"channel\"=\"sms\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"tenant_id\""] },
    { title = "OTP sends by channel (SMS vs WhatsApp)", filter = "metric.type=\"${local.lm}/farmerapp_otp_sent\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"channel\""] },
    { title = "LLM input tokens by tenant (LLM spend)", filter = "metric.type=\"${local.lm}/farmerapp_llm_input_tokens\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"tenant_id\""] },
    { title = "LLM output tokens by tenant", filter = "metric.type=\"${local.lm}/farmerapp_llm_output_tokens\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"tenant_id\""] },
    { title = "LLM calls by outcome", filter = "metric.type=\"${local.lm}/farmerapp_llm_calls\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"outcome\""] },
    { title = "Billable activity by tenant (the cost-split weight)", filter = "metric.type=starts_with(\"${local.lm}/farmerapp_visits_created\")", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"tenant_id\""] },
  ]

  business_note = <<-EOT
    Business ops (SPEC 12.4) from log-based metrics. `visits_created`, `orders_created`, `payments_captured`, `flag_raised` and the `ops_snapshot` gauges (officers on duty, open flags) are API log events (emitted since M5 API: visits, orders, payments, flags on write; ops_snapshot every 15 min from officer-sync-silence). Field contract: docs/runbooks/observability.md. The console owner home (WC-001) remains the source of truth for tenant figures.
  EOT

  # SPEC 12.4 asks for "cost by service and by tenant". Cloud Monitoring cannot query
  # BigQuery, and GCP publishes no spend metric, so the rupees live in the BigQuery views of
  # modules/cost and this dashboard carries what Monitoring *can* show: the usage drivers
  # behind each line of the bill, plus the two vendors (LLM, SMS) that never appear on the
  # GCP bill at all and are metered per tenant from the API's own log lines.
  cost_note = <<-EOT
    **Cost (SPEC 12.4, OPS-012, NF-015).**${var.monthly_budget_inr > 0 ? " Budget for this environment: **Rs ${var.monthly_budget_inr}/month** (infrastructure only; NF-015 excludes SMS and LLM)." : ""}

    Rupee figures - cost by service, by SKU, by tenant, and the day-on-day anomaly OPS-012 alerts on - are BigQuery views${var.cost_dataset != "" ? " in `${var.cost_dataset}`" : " in the cost dataset"} over the Cloud Billing export (`v_cost_daily_by_service`, `v_cost_daily_by_sku`, `v_cost_anomaly_daily`, `v_cost_daily_by_tenant`, `v_cost_monthly_vs_budget`). Point Looker Studio at them for the money view; see docs/cost-model.md for the model and its assumptions, and docs/runbooks/cost-and-budget.md for what to do when a number moves.

    The tiles below are the *drivers*: Cloud Run instance time (the biggest infra line), Cloud SQL sizing, log ingestion, BigQuery scan volume and storage growth. SMS and LLM are per tenant because they are the two costs that scale with one tenant's behaviour rather than with the platform.

    Cost by tenant is an **apportionment**, not a measurement: every GCP resource here is shared, so shared spend is split by each tenant's share of the day's visits and order lines. LLM and SMS are genuinely metered per tenant. The limits are written out in `infra/modules/cost/views.tf` and docs/cost-model.md - do not invoice a customer from this view without reading them.
  EOT

  dashboards = {
    platform = { title = "FarmerApp ${var.env} platform", tiles = local.platform_tiles, note = "" }
    business = { title = "FarmerApp ${var.env} business ops", tiles = local.business_tiles, note = local.business_note }
    cost     = { title = "FarmerApp ${var.env} cost", tiles = local.cost_tiles, note = local.cost_note }
  }
}

resource "google_monitoring_dashboard" "d" {
  for_each = var.dashboard_enabled ? local.dashboards : {}

  project = var.project_id
  dashboard_json = jsonencode({
    displayName = each.value.title
    labels      = { farmerapp = "" }
    mosaicLayout = {
      columns = 12
      tiles = concat(
        each.value.note == "" ? [] : [{
          xPos   = 0
          yPos   = 0
          width  = 12
          height = 4
          widget = {
            title = "About this dashboard"
            text  = { content = each.value.note, format = "MARKDOWN" }
          }
        }],
        [
          for i, t in each.value.tiles : {
            xPos   = (i % 2) * 6
            yPos   = (each.value.note == "" ? 0 : 4) + floor(i / 2) * 4
            width  = 6
            height = 4
            widget = {
              title = t.title
              xyChart = {
                dataSets = [{
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = t.filter
                      aggregation = {
                        alignmentPeriod    = each.key == "platform" ? "60s" : "3600s"
                        perSeriesAligner   = t.aligner
                        crossSeriesReducer = t.reducer
                        groupByFields      = t.group
                      }
                    }
                  }
                  plotType = "LINE"
                }]
              }
            }
          }
        ],
      )
    }
  })
}
