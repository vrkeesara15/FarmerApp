# SPEC 12.1 service level objectives on the api service (NF-005, NF-006), 28-day rolling.
#
#   SLO                          SLI source                                     Alert
#   availability 99.5%           run.googleapis.com/request_count (5xx = bad)   burn 14x / 1 h (sev1), 6x / 6 h (sev2)
#   latency reads p95 < 300 ms   log metric farmerapp_api_read_latency          p95 > 300 ms for 15 min (sev2)
#   latency writes p95 < 600 ms  log metric farmerapp_api_write_latency         p95 > 600 ms for 15 min (sev2)
#   sync success 99%             farmerapp_sync_success / farmerapp_sync_requests   < 97% for 30 min = burn > 3x / 30 min (sev2)
#   payment webhook 99.9% < 2 min  farmerapp_webhook_processing (processing_ms) any webhook in DLQ (alerts.tf, sev1)
#   OTP delivery 98% in 30 s     farmerapp_otp_delivered / farmerapp_otp_sent{channel=sms}  < 95% for 10 min = burn > 2.5x / 10 min (sev1)
#   diagnosis turnaround p95 < 5 s   M6 (diagnosis engine): added with DX-*.
#
# "p95 < X" is expressed as "95% of requests faster than X" (distribution cut), which is the
# same statement over the SLO window.

locals {
  slo_enabled = var.slo_enabled
  log_metric  = "logging.googleapis.com/user"
  run_api     = "resource.type=\"cloud_run_revision\" AND resource.label.\"service_name\"=\"${var.api_service_name}\""
}

resource "google_monitoring_custom_service" "api" {
  count = local.slo_enabled ? 1 : 0

  project      = var.project_id
  service_id   = "farmerapp-${var.env}-api"
  display_name = "FarmerApp ${var.env} API"

  user_labels = local.common_labels
}

resource "google_monitoring_slo" "availability" {
  count = local.slo_enabled ? 1 : 0

  project             = var.project_id
  service             = google_monitoring_custom_service.api[0].service_id
  slo_id              = "availability"
  display_name        = "API availability (non-5xx) ${var.availability_goal * 100}% / 28 d"
  goal                = var.availability_goal
  rolling_period_days = 28

  request_based_sli {
    good_total_ratio {
      bad_service_filter   = "metric.type=\"run.googleapis.com/request_count\" AND ${local.run_api} AND metric.label.\"response_code_class\"=\"5xx\""
      total_service_filter = "metric.type=\"run.googleapis.com/request_count\" AND ${local.run_api}"
    }
  }

  user_labels = merge(local.common_labels, { nf = "nf-006" })
}

resource "google_monitoring_slo" "latency" {
  for_each = local.slo_enabled ? { read = 300, write = 600 } : {}

  project             = var.project_id
  service             = google_monitoring_custom_service.api[0].service_id
  slo_id              = "latency-${each.key}"
  display_name        = "API ${each.key} latency p95 < ${each.value} ms / 28 d"
  goal                = 0.95
  rolling_period_days = 28

  request_based_sli {
    distribution_cut {
      distribution_filter = "metric.type=\"${local.log_metric}/${google_logging_metric.distribution["api_${each.key}_latency"].name}\" AND resource.type=\"cloud_run_revision\""
      range {
        min = 0
        max = each.value
      }
    }
  }

  user_labels = merge(local.common_labels, { nf = "nf-005" })
}

resource "google_monitoring_slo" "sync" {
  count = local.slo_enabled ? 1 : 0

  project             = var.project_id
  service             = google_monitoring_custom_service.api[0].service_id
  slo_id              = "sync-success"
  display_name        = "Sync success 99% / 28 d"
  goal                = 0.99
  rolling_period_days = 28

  request_based_sli {
    good_total_ratio {
      good_service_filter  = "metric.type=\"${local.log_metric}/${google_logging_metric.counter["sync_success"].name}\" AND resource.type=\"cloud_run_revision\""
      total_service_filter = "metric.type=\"${local.log_metric}/${google_logging_metric.counter["sync_requests"].name}\" AND resource.type=\"cloud_run_revision\""
    }
  }

  user_labels = local.common_labels
}

resource "google_monitoring_slo" "webhook" {
  count = local.slo_enabled ? 1 : 0

  project             = var.project_id
  service             = google_monitoring_custom_service.api[0].service_id
  slo_id              = "payment-webhook-2min"
  display_name        = "Payment webhook processed within 2 min 99.9% / 28 d"
  goal                = 0.999
  rolling_period_days = 28

  request_based_sli {
    distribution_cut {
      distribution_filter = "metric.type=\"${local.log_metric}/${google_logging_metric.distribution["webhook_processing"].name}\" AND resource.type=\"cloud_run_revision\""
      range {
        min = 0
        max = 120000
      }
    }
  }

  user_labels = local.common_labels
}

resource "google_monitoring_slo" "otp" {
  count = local.slo_enabled ? 1 : 0

  project             = var.project_id
  service             = google_monitoring_custom_service.api[0].service_id
  slo_id              = "otp-delivery-30s"
  display_name        = "OTP SMS delivered within 30 s 98% / 28 d"
  goal                = 0.98
  rolling_period_days = 28

  request_based_sli {
    good_total_ratio {
      good_service_filter  = "metric.type=\"${local.log_metric}/${google_logging_metric.counter["otp_delivered"].name}\" AND resource.type=\"cloud_run_revision\""
      total_service_filter = "metric.type=\"${local.log_metric}/${google_logging_metric.counter["otp_sent"].name}\" AND resource.type=\"cloud_run_revision\" AND metric.label.\"channel\"=\"sms\""
    }
  }

  user_labels = local.common_labels
}

# --- burn-rate alerts ------------------------------------------------------------------

locals {
  burn_alerts = local.slo_enabled ? {
    availability-fast = {
      slo     = google_monitoring_slo.availability[0].name, window = "60m", burn = 14, sev = "sev1", owner = "platform-lead"
      title   = "API availability burning 14x budget over 1 h"
      runbook = local.runbook.platform
    }
    availability-slow = {
      slo     = google_monitoring_slo.availability[0].name, window = "360m", burn = 6, sev = "sev2", owner = "platform-lead"
      title   = "API availability burning 6x budget over 6 h"
      runbook = local.runbook.platform
    }
    sync = {
      # 99% goal -> 1% budget; success < 97% = 3% errors = 3x burn.
      slo     = google_monitoring_slo.sync[0].name, window = "30m", burn = 3, sev = "sev2", owner = "mobile-lead"
      title   = "Sync success below 97% for 30 min"
      runbook = local.runbook.location
    }
    otp = {
      # 98% goal -> 2% budget; delivery < 95% = 5% failures = 2.5x burn. Action: switch provider.
      slo     = google_monitoring_slo.otp[0].name, window = "10m", burn = 2.5, sev = "sev1", owner = "platform-lead"
      title   = "OTP delivery below 95% for 10 min"
      runbook = local.runbook.otp
    }
  } : {}
}

resource "google_monitoring_alert_policy" "slo_burn" {
  for_each = local.burn_alerts

  project      = var.project_id
  display_name = "[${var.env}] SLO: ${each.value.title} (${each.value.sev})"
  combiner     = "OR"
  severity     = local.gcp_severity[each.value.sev]

  conditions {
    display_name = "burn rate > ${each.value.burn} over ${each.value.window}"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"${each.value.slo}\", \"${each.value.window}\")"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.burn
      duration        = "0s"
    }
  }

  notification_channels = local.channels[each.value.sev]
  user_labels           = merge(local.common_labels, { slo = each.key, owner = each.value.owner, sev = each.value.sev })

  documentation {
    subject   = "[${var.env}] ${each.value.title}"
    mime_type = "text/markdown"
    content   = <<-EOT
      **SLO alert (SPEC 12.1): ${each.value.title}.** Error-budget burn rate above ${each.value.burn}x over ${each.value.window}.

      - Owner: ${each.value.owner}
      - Severity: ${each.value.sev == "sev1" ? "Sev 1, page" : "Sev 2, ticket"}
      - Runbook: ${each.value.runbook}
    EOT
  }
}

resource "google_monitoring_alert_policy" "latency" {
  for_each = local.slo_enabled ? { read = 300, write = 600 } : {}

  project      = var.project_id
  display_name = "[${var.env}] SLO: API ${each.key} p95 > ${each.value} ms for 15 min (sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "p95 ${each.key} latency > ${each.value} ms"
    condition_threshold {
      filter          = "metric.type=\"${local.log_metric}/${google_logging_metric.distribution["api_${each.key}_latency"].name}\" AND resource.type=\"cloud_run_revision\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value
      duration        = "900s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_PERCENTILE_95"
      }
    }
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { slo = "latency-${each.key}", owner = "platform-lead", sev = "sev2", nf = "nf-005" })

  documentation {
    subject   = "[${var.env}] API ${each.key} latency p95 above ${each.value} ms"
    mime_type = "text/markdown"
    content   = <<-EOT
      **SLO alert (SPEC 12.1, NF-005): API ${each.key} p95 above ${each.value} ms for 15 minutes.** Check Cloud SQL CPU / connections and Query Insights, then Cloud Run instance count (max instances reached?).

      - Owner: platform lead
      - Severity: Sev 2, ticket
      - Runbook: ${local.runbook.platform}
    EOT
  }
}
