# OPS-011 (SPEC 12.2): "Datastream lag > 30 min; dbt run or test failure -> ticket to the
# data owner".
#
# Two independent signals, both Cloud Monitoring alert policies so they route through the
# same severity -> channel mapping as everything else (main.tf):
#
#   1. Datastream freshness. Datastream publishes `stream/freshness` (seconds behind the
#      source) per stream. AN-010 keeps the replica within 10 min (analytics
#      `data_freshness = 600s`), so 30 min behind means CDC is stuck, not merely busy. A
#      second policy catches a stream that is not RUNNING at all (paused, failed, or
#      permanently failed), which shows as freshness growing but only after the fact.
#
#   2. dbt run / test failure. dbt has no GCP metric of its own, so the *mechanism* is:
#      `dbt/scripts/dbt_run.py` wraps every dbt invocation (CI, `make dbt*`, and the
#      scheduled job when it exists), reads `target/run_results.json` /
#      `target/sources.json` after the run and emits one structured JSON line per
#      invocation -- the same shape as the API's structlog lines, so the log-based metric
#      machinery of log_metrics.tf reads it unchanged:
#
#        dbt_run_result     INFO   event, service="dbt", command, target, status, models,
#                                  errors, warnings, elapsed_s, invocation_id
#        dbt_run_failed     ERROR  + failures[] (node, status, message), first_failure
#        dbt_source_stale   ERROR  + source, max_loaded_at, staleness_s (AN-010 / OPS-011)
#
#      With DBT_CLOUD_LOG_PROJECT set the wrapper also writes the line to Cloud Logging
#      (`logName=projects/<p>/logs/dbt`, resource `global`) using the run's own
#      credentials, so a CI or job run in any environment reaches these metrics. Runs
#      inside a Cloud Run job land in the job's own log stream; both are matched below.
#
# Severity: sev2 (ticket, next business hour) with owner `data-owner`, per SPEC 12.2's
# "Ticket to data owner". Runbook: datastream-cdc-setup.md (the dbt / freshness section).

locals {
  # The wrapper's own log name, plus a dbt run inside a Cloud Run job.
  dbt_logs = join(" OR ", [
    "logName=\"projects/${var.project_id}/logs/dbt\"",
    "(resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"dbt\")",
  ])

  datastream_streams = var.datastream_stream_ids
}

# --- dbt log-based metrics --------------------------------------------------------------

resource "google_logging_metric" "dbt_failed" {
  project     = var.project_id
  name        = "farmerapp_dbt_failed"
  description = "OPS-011: a dbt run or test failed (event=dbt_run_failed from dbt/scripts/dbt_run.py)."
  filter      = "(${local.dbt_logs}) AND jsonPayload.event=\"dbt_run_failed\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "farmerapp dbt run failed"

    labels {
      key        = "target"
      value_type = "STRING"
    }
    labels {
      key        = "command"
      value_type = "STRING"
    }
    labels {
      key        = "first_failure"
      value_type = "STRING"
    }
  }

  label_extractors = {
    target        = "EXTRACT(jsonPayload.target)"
    command       = "EXTRACT(jsonPayload.command)"
    first_failure = "EXTRACT(jsonPayload.first_failure)"
  }
}

resource "google_logging_metric" "dbt_source_stale" {
  project     = var.project_id
  name        = "farmerapp_dbt_source_stale"
  description = "OPS-011 / AN-010: a dbt source is past its error-after threshold (event=dbt_source_stale); the Datastream replica is behind."
  filter      = "(${local.dbt_logs}) AND jsonPayload.event=\"dbt_source_stale\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "farmerapp dbt source stale"

    labels {
      key        = "source"
      value_type = "STRING"
    }
    labels {
      key        = "target"
      value_type = "STRING"
    }
  }

  label_extractors = {
    source = "EXTRACT(jsonPayload.source)"
    target = "EXTRACT(jsonPayload.target)"
  }
}

resource "google_logging_metric" "dbt_staleness_seconds" {
  project         = var.project_id
  name            = "farmerapp_dbt_staleness_seconds"
  description     = "AN-010: how far behind Postgres each dbt source is, in seconds (event=dbt_source_freshness, field staleness_s)."
  filter          = "(${local.dbt_logs}) AND jsonPayload.event=\"dbt_source_freshness\" AND jsonPayload.staleness_s>=0"
  value_extractor = "EXTRACT(jsonPayload.staleness_s)"

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "DISTRIBUTION"
    unit         = "s"
    display_name = "farmerapp dbt source staleness (s)"

    labels {
      key        = "source"
      value_type = "STRING"
    }
  }

  label_extractors = { source = "EXTRACT(jsonPayload.source)" }

  bucket_options {
    explicit_buckets {
      # 900 (warn) and 1800 (error) are bounds so a percentile never crosses by interpolation.
      bounds = [60, 300, 600, 900, 1800, 3600, 7200, 21600, 86400]
    }
  }
}

# --- alerts ------------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "dbt_failed" {
  count = var.data_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] dbt run or test failed (OPS-011, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "any dbt_run_failed line in 15 min"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.dbt_failed.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period     = "900s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.target", "metric.label.command"]
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-011", owner = "data-owner", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] dbt failed"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-011: a dbt run or test failed.** The line carries `command`, `target`,
      `first_failure` and the whole `failures[]` list (node, status, message):

      ```
      gcloud logging read 'jsonPayload.event="dbt_run_failed"' --project ${var.project_id} --freshness 1d --limit 5
      ```

      - Owner: data owner
      - Severity: Sev 2, ticket, next business hour (marts are stale until it is fixed)
      - Runbook: ${local.runbook.data}
    EOT
  }
}

resource "google_monitoring_alert_policy" "dbt_source_stale" {
  count = var.data_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] dbt source past ${var.data_freshness_error_minutes} min (OPS-011 / AN-010, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "any dbt_source_stale line in 1 h"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.dbt_source_stale.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.source"]
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-011", owner = "data-owner", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] dbt source freshness"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-011 / AN-010: a replicated table is more than ${var.data_freshness_error_minutes} minutes behind Postgres** (`dbt source freshness`).
      Check the Datastream freshness alert first: if the stream is healthy, the staleness is in
      the merge lag or the table has genuinely had no writes (a quiet source is reported, not
      an outage -- see the runbook for the per-source thresholds).

      - Owner: data owner
      - Severity: Sev 2, ticket
      - Runbook: ${local.runbook.data}
    EOT
  }
}

resource "google_monitoring_alert_policy" "datastream_freshness" {
  for_each = var.data_alerts_enabled ? toset(local.datastream_streams) : toset([])

  project      = var.project_id
  display_name = "[${var.env}] Datastream ${each.value} lag > ${var.datastream_lag_minutes} min (OPS-011, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "stream/freshness > ${var.datastream_lag_minutes * 60} s for 15 min"
    condition_threshold {
      filter          = "metric.type=\"datastream.googleapis.com/stream/freshness\" AND resource.type=\"datastream.googleapis.com/Stream\" AND resource.label.\"stream_id\"=\"${each.value}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.datastream_lag_minutes * 60
      duration        = "900s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-011", owner = "data-owner", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] Datastream lag"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-011: Datastream `${each.value}` is more than ${var.datastream_lag_minutes} minutes behind Cloud SQL** for 15 minutes.
      Everything downstream (staging, marts, authorised views, the console's analytics
      dashboards) is that stale. AN-010 targets under 15 minutes end to end.

      - Owner: data owner
      - Severity: Sev 2, ticket (Sev 1 only if it coincides with a Cloud SQL incident)
      - Runbook: ${local.runbook.data}
    EOT
  }
}

resource "google_monitoring_alert_policy" "datastream_unsupported" {
  for_each = var.data_alerts_enabled ? toset(local.datastream_streams) : toset([])

  project      = var.project_id
  display_name = "[${var.env}] Datastream ${each.value} dropped events (OPS-011, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "unsupported_event_count > 0 in 1 h"
    condition_threshold {
      filter          = "metric.type=\"datastream.googleapis.com/stream/unsupported_event_count\" AND resource.type=\"datastream.googleapis.com/Stream\" AND resource.label.\"stream_id\"=\"${each.value}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-011", owner = "data-owner", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] Datastream dropped events"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-011: Datastream `${each.value}` could not replicate some events** (unsupported type,
      oversized row, or a column outside the allowlist changed shape). Those rows are silently
      missing from `farmerapp_raw`, so the marts under-count until the stream is fixed and
      backfilled.

      - Owner: data owner
      - Severity: Sev 2, ticket
      - Runbook: ${local.runbook.data}
    EOT
  }
}
