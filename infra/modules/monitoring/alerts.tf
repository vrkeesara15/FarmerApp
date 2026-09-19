# OPS-002..OPS-005 alert policies. SPEC 12.2 "Action" column -> severity:
#   OPS-002 error rate                      sev2 (halt staged rollout: runbook)
#   OPS-003 Cloud SQL                       ticket (sev2) after 5 min; page (sev1) if sustained 30 min
#   OPS-004 Pub/Sub backlog / DLQ           ticket (sev2) + DLQ replay runbook; payment.webhook is sev1
#   OPS-005 Cloud Run job failure           ticket (sev2), next-morning owner

# --- OPS-002 error rate ---------------------------------------------------------
# Server-side error ratio per LB-fronted / push service from Cloud Run's request_count
# (response_code_class = 5xx). Error Reporting groups the stack traces of the same errors
# (new-group notifications are set in the console: no Terraform resource); crash-free
# sessions per app version live in Firebase Crashlytics (bad-mobile-release-rollback.md).

resource "google_monitoring_alert_policy" "error_rate" {
  for_each = var.error_rate_alerts_enabled ? toset(var.error_rate_services) : toset([])

  project      = var.project_id
  display_name = "[${var.env}] ${each.value} 5xx ratio > ${var.error_rate_threshold * 100}% (OPS-002, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "5xx / all requests > ${var.error_rate_threshold * 100}% for 10 min"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.\"service_name\"=\"${each.value}\" AND metric.label.\"response_code_class\"=\"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.error_rate_threshold
      duration        = "600s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      denominator_filter = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.\"service_name\"=\"${each.value}\""
      denominator_aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-002", owner = "platform-lead", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] ${each.value} error rate high"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-002: ${each.value} returns 5xx for more than ${var.error_rate_threshold * 100}% of requests** over 10 minutes.

      - Owner: platform lead
      - Severity: Sev 2, Slack channel, next business hour (page if the availability SLO burn-rate alert also fires)
      - Runbook: ${local.runbook.platform} (roll back the last revision; Error Reporting for the top error group)
    EOT
  }
}

# Unhandled exceptions logged by the API / worker / jobs (`event=unhandled_error` and other
# level=error lines, see log_metrics.tf). A sudden burst after a deploy halts the rollout.
resource "google_monitoring_alert_policy" "app_errors" {
  count = var.error_rate_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] application error burst (OPS-002, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "error-level log lines > ${var.app_error_burst_per_5m} in 5 min"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.counter["app_errors"].name}\" AND resource.type=\"cloud_run_revision\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.app_error_burst_per_5m
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.service_name"]
      }
    }
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-002", owner = "platform-lead", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] application errors"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-002: more than ${var.app_error_burst_per_5m} error-level log lines in 5 minutes** in one Cloud Run service.

      - Owner: platform lead
      - Severity: Sev 2
      - Runbook: ${local.runbook.platform}
    EOT
  }
}

# --- OPS-003 Cloud SQL ------------------------------------------------------------

locals {
  sql_primary = var.sql_alerts_enabled && var.sql_instance_id != ""
  sql_replica = var.sql_alerts_enabled && var.sql_replica_instance_id != ""

  sql_conditions = merge(
    local.sql_primary ? {
      cpu = {
        desc   = "CPU > 80%", db = var.sql_instance_id, threshold = 0.8, reducer = null
        metric = "cloudsql.googleapis.com/database/cpu/utilization"
      }
      disk = {
        desc   = "storage > 80%", db = var.sql_instance_id, threshold = 0.8, reducer = null
        metric = "cloudsql.googleapis.com/database/disk/utilization"
      }
      connections = {
        desc      = "connections > 80% of max_connections (${var.sql_max_connections})", db = var.sql_instance_id
        threshold = floor(var.sql_max_connections * 0.8), reducer = "REDUCE_SUM"
        metric    = "cloudsql.googleapis.com/database/postgresql/num_backends"
      }
    } : {},
    local.sql_replica ? {
      replica_lag = {
        desc   = "replication lag > 60 s", db = var.sql_replica_instance_id, threshold = 60, reducer = null
        metric = "cloudsql.googleapis.com/database/replication/replica_lag"
      }
    } : {},
  )

  # Each condition twice: a ticket after 5 min, a page when it lasts 30 min (SPEC 12.2).
  sql_policies = merge(
    { for k, c in local.sql_conditions : "${k}-ticket" => merge(c, { sev = "sev2", duration = "300s", tier = "ticket" }) },
    { for k, c in local.sql_conditions : "${k}-page" => merge(c, { sev = "sev1", duration = "1800s", tier = "page, sustained 30 min" }) },
  )
}

resource "google_monitoring_alert_policy" "sql" {
  for_each = local.sql_policies

  project      = var.project_id
  display_name = "[${var.env}] Cloud SQL ${each.value.desc} (OPS-003, ${each.value.sev} ${each.value.tier})"
  combiner     = "OR"
  severity     = local.gcp_severity[each.value.sev]

  conditions {
    display_name = each.value.desc
    condition_threshold {
      filter          = "metric.type=\"${each.value.metric}\" AND resource.type=\"cloudsql_database\" AND resource.label.\"database_id\"=\"${each.value.db}\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = each.value.duration
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = each.value.reducer
        group_by_fields      = each.value.reducer == null ? null : ["resource.label.database_id"]
      }
    }
  }

  notification_channels = local.channels[each.value.sev]
  user_labels           = merge(local.common_labels, { ops = "ops-003", owner = "platform-lead", sev = each.value.sev })

  documentation {
    subject   = "[${var.env}] Cloud SQL ${each.value.desc}"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-003: Cloud SQL `${each.value.db}` ${each.value.desc}** for ${each.value.duration == "300s" ? "5 minutes (ticket)" : "30 minutes (page)"}.

      - Owner: platform lead
      - Severity: ${each.value.sev == "sev1" ? "Sev 1, page" : "Sev 2, ticket"}
      - Runbook: ${local.runbook.sql}
    EOT
  }
}

# --- OPS-004 Pub/Sub ----------------------------------------------------------------
# Per topic: the worker push subscription `<topic>.worker` backlog, and the DLQ replay
# subscription `<topic>.dlq.replay` (modules/pubsub) holding any message at all.

locals {
  pubsub_topics = var.pubsub_alerts_enabled ? toset(var.pubsub_topics) : toset([])
  # Payments are Sev 1 (payment failure, SPEC 12.3); every other topic is a ticket.
  topic_sev = { for t in var.pubsub_topics : t => contains(var.sev1_topics, t) ? "sev1" : "sev2" }
}

resource "google_monitoring_alert_policy" "pubsub_backlog" {
  for_each = local.pubsub_topics

  project      = var.project_id
  display_name = "[${var.env}] ${each.value}: oldest unacked > 10 min (OPS-004, ${local.topic_sev[each.value]})"
  combiner     = "OR"
  severity     = local.gcp_severity[local.topic_sev[each.value]]

  conditions {
    display_name = "${each.value}.worker oldest_unacked_message_age > 600 s"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" AND resource.type=\"pubsub_subscription\" AND resource.label.\"subscription_id\"=\"${each.value}.worker\""
      comparison      = "COMPARISON_GT"
      threshold_value = 600
      duration        = "60s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.channels[local.topic_sev[each.value]]
  user_labels           = merge(local.common_labels, { ops = "ops-004", owner = "platform-lead", sev = local.topic_sev[each.value] })

  documentation {
    subject   = "[${var.env}] Pub/Sub backlog on ${each.value}"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-004: subscription `${each.value}.worker` has a message older than 10 minutes.** The worker is failing, slow or scaled to its max.

      - Owner: platform lead${each.value == "payment.webhook" ? " + finance (payments)" : ""}
      - Severity: ${local.topic_sev[each.value] == "sev1" ? "Sev 1, page" : "Sev 2, ticket"}
      - Runbook: ${local.runbook.webhook} (the DLQ replay steps apply to every topic)
    EOT
  }
}

resource "google_monitoring_alert_policy" "pubsub_dlq" {
  for_each = local.pubsub_topics

  project      = var.project_id
  display_name = "[${var.env}] ${each.value}: message in dead-letter queue (OPS-004, ${local.topic_sev[each.value]})"
  combiner     = "OR"
  severity     = local.gcp_severity[local.topic_sev[each.value]]

  conditions {
    display_name = "${each.value}.dlq.replay num_undelivered_messages > 0"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.type=\"pubsub_subscription\" AND resource.label.\"subscription_id\"=\"${each.value}.dlq.replay\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = local.channels[local.topic_sev[each.value]]
  user_labels           = merge(local.common_labels, { ops = "ops-004", owner = "platform-lead", sev = local.topic_sev[each.value] })

  documentation {
    subject   = "[${var.env}] dead letters on ${each.value}"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-004: `${each.value}.dlq` holds messages** that failed 5 deliveries to the worker. They stay in `${each.value}.dlq.replay` (7-day retention) until replayed.

      - Owner: platform lead${each.value == "payment.webhook" ? " + finance (payment webhook SLO: any webhook in the DLQ breaches it)" : ""}
      - Severity: ${local.topic_sev[each.value] == "sev1" ? "Sev 1, page" : "Sev 2, ticket"}
      - Runbook: ${local.runbook.webhook} ("Replay a DLQ")
    EOT
  }
}

# --- OPS-005 Cloud Run job failures ------------------------------------------------

resource "google_monitoring_alert_policy" "job_failed" {
  for_each = var.job_alerts_enabled ? var.jobs : {}

  project      = var.project_id
  display_name = "[${var.env}] job ${each.key} failed (OPS-005, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "${each.key}: completed_execution_count{result=failed} > 0"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/job/completed_execution_count\" AND resource.type=\"cloud_run_job\" AND resource.label.\"job_name\"=\"${each.key}\" AND metric.label.\"result\"=\"failed\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-005", owner = each.value.owner, sev = "sev2" })

  documentation {
    subject   = "[${var.env}] job ${each.key} failed"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-005: Cloud Run job `${each.key}` finished with a failed execution** (${each.value.description}).

      - Owner: ${each.value.owner} (next morning)
      - Severity: Sev 2, ticket
      - Runbook: ${local.runbook.jobs}
    EOT
  }
}
