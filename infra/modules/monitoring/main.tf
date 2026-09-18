# SPEC 12: uptime checks (OPS-001), Cloud SQL (OPS-003), Pub/Sub (OPS-004),
# Cloud Run jobs (OPS-005), audit log export (SEC-017) and the platform
# dashboard (12.4). Business-metric monitors (OPS-006..010) are emitted by
# jobs and wired later as log-based metrics.

locals {
  channels = concat(
    var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : [],
    var.extra_notification_channels,
  )
  common_labels = { app = "farmerapp", env = var.env }
}

resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != "" ? 1 : 0

  project      = var.project_id
  display_name = "FarmerApp ${var.env} on-call email"
  type         = "email"
  labels = {
    email_address = var.notification_email
  }
}

# --- OPS-001 uptime -------------------------------------------------------

resource "google_monitoring_uptime_check_config" "http" {
  for_each = var.uptime_checks

  project          = var.project_id
  display_name     = "farmerapp-${var.env}-${each.key}"
  timeout          = "10s"
  period           = "60s"
  selected_regions = ["ASIA_PACIFIC", "EUROPE", "USA_OREGON"]

  http_check {
    path         = each.value.path
    port         = 443
    use_ssl      = true
    validate_ssl = true
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = each.value.host
    }
  }
}

resource "google_monitoring_alert_policy" "uptime" {
  for_each = var.uptime_checks

  project      = var.project_id
  display_name = "[${var.env}] ${each.key} down (OPS-001)"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "Uptime check failing from 2+ regions"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.\"check_id\"=\"${google_monitoring_uptime_check_config.http[each.key].uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "300s"
      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.channels
  user_labels           = merge(local.common_labels, { runbook = "docs/runbooks/README.md", ops = "ops-001" })

  documentation {
    content   = "Uptime check ${each.key} (${each.value.host}${each.value.path}) failing. Page on-call. Runbook: docs/runbooks/"
    mime_type = "text/markdown"
  }
}

# --- OPS-003 Cloud SQL ------------------------------------------------------

locals {
  sql_metrics = var.sql_alerts_enabled && var.sql_instance_id != "" ? {
    cpu         = { metric = "cloudsql.googleapis.com/database/cpu/utilization", threshold = 0.8, desc = "CPU > 80%" }
    disk        = { metric = "cloudsql.googleapis.com/database/disk/utilization", threshold = 0.8, desc = "storage > 80%" }
    replica_lag = { metric = "cloudsql.googleapis.com/database/replication/replica_lag", threshold = 60, desc = "replication lag > 60 s" }
  } : {}
}

resource "google_monitoring_alert_policy" "sql" {
  for_each = local.sql_metrics

  project      = var.project_id
  display_name = "[${var.env}] Cloud SQL ${each.value.desc} (OPS-003)"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = each.value.desc
    condition_threshold {
      filter          = "metric.type=\"${each.value.metric}\" AND resource.type=\"cloudsql_database\" AND resource.label.\"database_id\"=\"${var.sql_instance_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "1800s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.channels
  user_labels           = merge(local.common_labels, { ops = "ops-003" })
}

# --- OPS-004 Pub/Sub --------------------------------------------------------

resource "google_monitoring_alert_policy" "pubsub_backlog" {
  count = var.pubsub_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] Pub/Sub oldest unacked > 10 min (OPS-004)"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "oldest_unacked_message_age > 600s"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" AND resource.type=\"pubsub_subscription\""
      comparison      = "COMPARISON_GT"
      threshold_value = 600
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.channels
  user_labels           = merge(local.common_labels, { ops = "ops-004" })
}

resource "google_monitoring_alert_policy" "pubsub_dlq" {
  count = var.pubsub_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] Message in a dead-letter topic (OPS-004)"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "any message published to *.dlq"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\" AND resource.type=\"pubsub_topic\" AND resource.label.\"topic_id\"=monitoring.regex.full_match(\".*\\\\.dlq\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.channels
  user_labels           = merge(local.common_labels, { ops = "ops-004", runbook = "dlq-replay" })
}

# --- OPS-005 Cloud Run job failures ---------------------------------------

resource "google_monitoring_alert_policy" "job_failed" {
  count = var.job_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] Cloud Run job failed (OPS-005)"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "completed_execution_count{result=failed} > 0"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/job/completed_execution_count\" AND resource.type=\"cloud_run_job\" AND metric.label.\"result\"=\"failed\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.channels
  user_labels           = merge(local.common_labels, { ops = "ops-005" })
}

# --- SEC-017 audit logs → locked bucket, 400 days ---------------------------

resource "google_logging_project_bucket_config" "audit" {
  project        = var.project_id
  location       = var.region
  bucket_id      = "farmerapp-audit"
  retention_days = var.audit_log_retention_days
  locked         = var.lock_audit_bucket
  description    = "Admin Activity + Data Access audit logs (SEC-017)"
}

resource "google_logging_project_sink" "audit" {
  project                = var.project_id
  name                   = "farmerapp-audit-sink"
  destination            = "logging.googleapis.com/${google_logging_project_bucket_config.audit.id}"
  filter                 = "logName:\"cloudaudit.googleapis.com\""
  unique_writer_identity = true
}

resource "google_project_iam_audit_config" "data_access" {
  for_each = toset(["sqladmin.googleapis.com", "secretmanager.googleapis.com", "storage.googleapis.com"])

  project = var.project_id
  service = each.value

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# --- 12.4 platform dashboard -------------------------------------------------

resource "google_monitoring_dashboard" "platform" {
  count = var.dashboard_enabled ? 1 : 0

  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "FarmerApp ${var.env} platform"
    mosaicLayout = {
      columns = 12
      tiles = [
        for i, t in [
          { title = "Cloud Run request count", filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\"", reducer = "REDUCE_SUM", aligner = "ALIGN_RATE" },
          { title = "Cloud Run 5xx", filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" metric.label.\"response_code_class\"=\"5xx\"", reducer = "REDUCE_SUM", aligner = "ALIGN_RATE" },
          { title = "Cloud Run latency p95", filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\"", reducer = "REDUCE_PERCENTILE_95", aligner = "ALIGN_DELTA" },
          { title = "Cloud Run instances", filter = "metric.type=\"run.googleapis.com/container/instance_count\" resource.type=\"cloud_run_revision\"", reducer = "REDUCE_SUM", aligner = "ALIGN_MAX" },
          { title = "Cloud SQL CPU", filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\"", reducer = "REDUCE_MEAN", aligner = "ALIGN_MEAN" },
          { title = "Pub/Sub oldest unacked age", filter = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" resource.type=\"pubsub_subscription\"", reducer = "REDUCE_MAX", aligner = "ALIGN_MAX" },
          ] : {
          xPos   = (i % 2) * 6
          yPos   = floor(i / 2) * 4
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
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = t.aligner
                      crossSeriesReducer = t.reducer
                      groupByFields      = ["resource.label.\"service_name\""]
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })
}
