# OPS-009 (SPEC 12.2) / DX-006: diagnosis review queue age and LLM fallback rate.
#
# Source: the hourly Cloud Run job `diagnosis-queue-age` (python -m farmerapp.jobs
# diagnosis-queue-age, apps/api/farmerapp/ops/diagnosis_watch.py) logs, per tenant:
#   diagnosis_queue_snapshot     INFO    tenant_id, queue, overdue, oldest_hours (null if empty)
#   diagnosis_queue_aged         WARNING tenant_id, newly_overdue, overdue, oldest_hours, notified
#   diagnosis_llm_fallback_rate  INFO    tenant_id, day (IST), answered, llm_fallbacks, rate
#   diagnosis_llm_fallback_alert WARNING tenant_id, day, rate, threshold (0.4), answered (>= 5)
# The job already notifies agronomists in the app; these alerts reach the on-call owner.

locals {
  diagnosis_job_logs = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"diagnosis-queue-age\""
}

resource "google_logging_metric" "diagnosis_queue_oldest_hours" {
  project         = var.project_id
  name            = "farmerapp_diagnosis_queue_oldest_hours"
  description     = "OPS-009: age in hours of the oldest diagnosis in the agronomist review queue (event=diagnosis_queue_snapshot, hourly)."
  filter          = "${local.diagnosis_job_logs} AND jsonPayload.event=\"diagnosis_queue_snapshot\" AND jsonPayload.oldest_hours>=0"
  value_extractor = "EXTRACT(jsonPayload.oldest_hours)"

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "DISTRIBUTION"
    unit         = "h"
    display_name = "farmerapp diagnosis review queue oldest (h)"
    labels {
      key        = "tenant_id"
      value_type = "STRING"
    }
  }

  label_extractors = { tenant_id = "EXTRACT(jsonPayload.tenant_id)" }

  bucket_options {
    explicit_buckets {
      # 18 is a bound so the percentile estimate never crosses the alert threshold by interpolation.
      bounds = [1, 2, 4, 6, 12, 18, 24, 36, 48, 72, 168]
    }
  }
}

resource "google_logging_metric" "diagnosis_queue_aged" {
  project     = var.project_id
  name        = "farmerapp_diagnosis_queue_aged"
  description = "OPS-009: diagnoses newly past 18 h in the review queue (event=diagnosis_queue_aged, one line per run with any)."
  filter      = "${local.diagnosis_job_logs} AND jsonPayload.event=\"diagnosis_queue_aged\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "farmerapp diagnosis queue aged"
    labels {
      key        = "tenant_id"
      value_type = "STRING"
    }
  }

  label_extractors = { tenant_id = "EXTRACT(jsonPayload.tenant_id)" }
}

resource "google_logging_metric" "diagnosis_llm_fallback_rate" {
  project         = var.project_id
  name            = "farmerapp_diagnosis_llm_fallback_rate"
  description     = "OPS-009: share (0..1) of today's (IST) answered diagnoses that needed the LLM fallback (event=diagnosis_llm_fallback_rate, hourly)."
  filter          = "${local.diagnosis_job_logs} AND jsonPayload.event=\"diagnosis_llm_fallback_rate\" AND jsonPayload.rate>=0"
  value_extractor = "EXTRACT(jsonPayload.rate)"

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "DISTRIBUTION"
    unit         = "1"
    display_name = "farmerapp diagnosis LLM fallback rate"
    labels {
      key        = "tenant_id"
      value_type = "STRING"
    }
  }

  label_extractors = { tenant_id = "EXTRACT(jsonPayload.tenant_id)" }

  bucket_options {
    explicit_buckets {
      bounds = [0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1]
    }
  }
}

resource "google_logging_metric" "diagnosis_llm_fallback_alert" {
  project     = var.project_id
  name        = "farmerapp_diagnosis_llm_fallback_alert"
  description = "OPS-009: the job found the day's LLM fallback rate above 40 % with at least 5 answers (event=diagnosis_llm_fallback_alert)."
  filter      = "${local.diagnosis_job_logs} AND jsonPayload.event=\"diagnosis_llm_fallback_alert\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "farmerapp diagnosis LLM fallback alert"
    labels {
      key        = "tenant_id"
      value_type = "STRING"
    }
  }

  label_extractors = { tenant_id = "EXTRACT(jsonPayload.tenant_id)" }
}

# --- alerts ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "diagnosis_queue_age" {
  count = var.diagnosis_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] diagnosis review queue older than ${var.diagnosis_queue_age_hours} h (OPS-009, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "oldest queued diagnosis > ${var.diagnosis_queue_age_hours} h (per tenant)"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.diagnosis_queue_oldest_hours.name}\" AND resource.type=\"cloud_run_job\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.diagnosis_queue_age_hours
      duration        = "0s"
      aggregations {
        alignment_period     = "3600s" # the job runs hourly
        per_series_aligner   = "ALIGN_PERCENTILE_99"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = ["metric.label.tenant_id"]
      }
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "7200s" # closes after two clean hourly runs
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-009", owner = "agronomist-lead", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] diagnosis review queue > ${var.diagnosis_queue_age_hours} h"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-009 / DX-006: a farmer's provisional or out-of-scope diagnosis has waited more than ${var.diagnosis_queue_age_hours} h** for an agronomist (tenant in the incident labels). Agronomists were already notified in the app by the `diagnosis-queue-age` job.

      - Owner: agronomist lead (reassign or add reviewers; the console review queue sorts oldest first)
      - Severity: Sev 2, ticket
      - Runbook: ${local.runbook.diagnosis}
    EOT
  }
}

resource "google_monitoring_alert_policy" "diagnosis_llm_rate" {
  count = var.diagnosis_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] diagnosis LLM fallback > ${var.diagnosis_llm_rate_percent}% today (OPS-009, sev3)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev3

  conditions {
    display_name = "diagnosis_llm_fallback_alert logged (rate > ${var.diagnosis_llm_rate_percent}%, >= 5 answers, IST day)"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.diagnosis_llm_fallback_alert.name}\" AND resource.type=\"cloud_run_job\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.tenant_id"]
      }
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "86400s" # one incident per tenant-day at most
  }

  notification_channels = local.channels.sev3
  user_labels           = merge(local.common_labels, { ops = "ops-009", owner = "agronomist-lead", sev = "sev3" })

  documentation {
    subject   = "[${var.env}] diagnosis LLM fallback rate high"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-009: more than ${var.diagnosis_llm_rate_percent}% of today's diagnoses (IST, at least 5) fell back to the LLM** instead of a confident corpus match. Usually a corpus gap (new pest, new crop stage, unseen region) or an encoder / threshold regression; every fallback is provisional and lands in the agronomist queue.

      - Owner: agronomist lead (corpus coverage) with the ML owner (encoder / thresholds)
      - Severity: Sev 3, daily digest
      - Runbook: ${local.runbook.diagnosis}
    EOT
  }
}
