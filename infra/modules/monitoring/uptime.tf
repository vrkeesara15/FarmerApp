# OPS-001: uptime checks on the API, the console and the Razorpay webhook endpoint from three
# regions, every 60 s, through the public load balancer (so DNS, certificate, Cloud Armor and
# Cloud Run are all exercised). Sev 1: pages on-call.
#
# The webhook endpoint only accepts POST (HMAC-signed); a GET must reach the app and answer
# 405, which proves the route is served without sending an unsigned event. Health and webhook
# paths are exempt from the Cloud Armor geo rule (modules/lb), otherwise the EUROPE / USA
# checkers would be blocked.

resource "google_monitoring_uptime_check_config" "http" {
  for_each = var.uptime_checks

  project          = var.project_id
  display_name     = "farmerapp-${var.env}-${each.key}"
  timeout          = "10s"
  period           = "60s"
  selected_regions = var.uptime_regions

  http_check {
    path           = each.value.path
    request_method = "GET"
    port           = 443
    use_ssl        = true
    validate_ssl   = true

    dynamic "accepted_response_status_codes" {
      for_each = each.value.accepted_status == null ? [1] : []
      content {
        status_class = "STATUS_CLASS_2XX"
      }
    }
    dynamic "accepted_response_status_codes" {
      for_each = each.value.accepted_status == null ? [] : [each.value.accepted_status]
      content {
        status_value = accepted_response_status_codes.value
      }
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = each.value.host
    }
  }

  user_labels = merge(local.common_labels, { ops = "ops-001" })
}

resource "google_monitoring_alert_policy" "uptime" {
  for_each = var.uptime_checks

  project      = var.project_id
  display_name = "[${var.env}] ${each.key} down (OPS-001, sev1)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev1

  conditions {
    display_name = "Uptime check failing from 2+ regions for 2 min"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.\"check_id\"=\"${google_monitoring_uptime_check_config.http[each.key].uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "120s"
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = local.channels.sev1
  user_labels           = merge(local.common_labels, { ops = "ops-001", owner = "platform-lead", sev = "sev1" })

  documentation {
    subject   = "[${var.env}] ${each.key} is down"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-001: ${each.key} uptime check failing** (`https://${each.value.host}${each.value.path}`) from two or more of ${join(", ", var.uptime_regions)}.

      - Owner: platform lead (on-call)
      - Severity: Sev 1, page, 15-minute response (SPEC 12.3)
      - Runbook: ${each.key == "webhook" ? local.runbook.webhook : local.runbook.platform}
    EOT
  }
}
