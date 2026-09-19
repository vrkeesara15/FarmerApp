# SPEC 12.4 dashboards: platform, business ops, cost (placeholder). The mobile dashboard
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
    { title = "OTP sends (SMS spend driver) by channel", filter = "metric.type=\"${local.lm}/farmerapp_otp_sent\"", aligner = "ALIGN_DELTA", reducer = "REDUCE_SUM", group = ["metric.label.\"channel\""] },
  ]

  business_note = <<-EOT
    Business ops (SPEC 12.4) from log-based metrics. `visits_created`, `orders_created`, `payments_captured`, `flag_raised` and the `ops_snapshot` gauges (officers on duty, open flags) are **expected** API log events: until the API emits them these charts stay empty. Field contract: docs/runbooks/observability.md. The console owner home (WC-001) remains the source of truth for tenant figures.
  EOT

  cost_note = <<-EOT
    **Cost (SPEC 12.4, OPS-012) - placeholder.** Spend by service and by tenant needs the Cloud Billing export to BigQuery (billing-account admin, human gate) and a dbt model joining SKU cost with tenant usage (LLM and SMS by tenant). Until then these tiles show the usage drivers that dominate the bill: Cloud Run instance time, Cloud SQL sizing and OTP SMS volume. Budget alerts (130% of 7-day average) are OPS-012, not in this change.
  EOT

  dashboards = {
    platform = { title = "FarmerApp ${var.env} platform", tiles = local.platform_tiles, note = "" }
    business = { title = "FarmerApp ${var.env} business ops", tiles = local.business_tiles, note = local.business_note }
    cost     = { title = "FarmerApp ${var.env} cost (placeholder)", tiles = local.cost_tiles, note = local.cost_note }
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
          height = 2
          widget = {
            title = "About this dashboard"
            text  = { content = each.value.note, format = "MARKDOWN" }
          }
        }],
        [
          for i, t in each.value.tiles : {
            xPos   = (i % 2) * 6
            yPos   = (each.value.note == "" ? 0 : 2) + floor(i / 2) * 4
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
