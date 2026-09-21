# OPS-013 (SPEC 12.2): "Security: SCC high findings, Cloud Armor spikes, OTP send spikes
# (SMS pumping) -> page on-call". All three are Sev 1 (page): a high SCC finding is a live
# exposure, an Armor spike is an attack in progress, and an OTP spike burns money and the
# DLT sender reputation within minutes.
#
#   SCC          Security Command Center is an org-level product. Terraform here creates the
#                landing topic and lets the SCC service agent publish to it; pointing SCC at
#                the topic needs org-level IAM and is a human gate (see the runbook / the
#                gcloud command in the alert documentation below). Any message on the topic
#                *is* a high/critical finding, because the notification config carries the
#                filter -- so the alert is "anything published".
#   Cloud Armor  the HTTPS load balancer logs every request with
#                `jsonPayload.enforcedSecurityPolicy` (modules/lb enables logging at 100% on
#                the api backend, 50% on console). A DENY outcome is a blocked request; a
#                spike of them means an attack or a misfiring rule locking real users out --
#                both need the on-call.
#   OTP          `farmerapp_otp_sent` (log_metrics.tf) carries `channel` and `tenant_id`. An
#                SMS-pumping attack shows as a sudden jump in sends for one tenant with no
#                matching jump in verifications.

# --- SCC ---------------------------------------------------------------------------------

resource "google_pubsub_topic" "scc_findings" {
  count = var.security_alerts_enabled ? 1 : 0

  project = var.project_id
  name    = var.scc_findings_topic
  labels  = local.common_labels
}

# The SCC notification service agent publishes findings here. The agent is per organisation
# (service-org-<org id>@gcp-sa-scc-notification.iam.gserviceaccount.com); with no org id set
# the binding is skipped and the topic simply stays empty.
resource "google_pubsub_topic_iam_member" "scc_publisher" {
  count = var.security_alerts_enabled && var.scc_organization_id != "" ? 1 : 0

  project = var.project_id
  topic   = google_pubsub_topic.scc_findings[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-org-${var.scc_organization_id}@gcp-sa-scc-notification.iam.gserviceaccount.com"
}

resource "google_monitoring_alert_policy" "scc_high" {
  count = var.security_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] Security Command Center high finding (OPS-013, sev1)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev1

  conditions {
    display_name = "a finding was published to ${var.scc_findings_topic}"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/topic/send_request_count\" AND resource.type=\"pubsub_topic\" AND resource.label.\"topic_id\"=\"${var.scc_findings_topic}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = local.channels.sev1
  user_labels           = merge(local.common_labels, { ops = "ops-013", owner = "platform-lead", sev = "sev1" })

  documentation {
    subject   = "[${var.env}] SCC high finding"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-013: Security Command Center published a HIGH or CRITICAL finding** for this project.

      ```
      gcloud scc findings list <org id> --filter='state="ACTIVE" AND severity="HIGH"' --source=-
      ```

      - Owner: platform lead (on-call), security owner in the loop
      - Severity: Sev 1, page, 15-minute response
      - Runbook: ${local.runbook.breach} (treat as a possible breach until triaged)

      **Human gate (once per organisation):** point SCC at this topic --
      `gcloud scc notifications create farmerapp-${var.env}-high --organization=<org id>
      --pubsub-topic=projects/${var.project_id}/topics/${var.scc_findings_topic}
      --filter='state="ACTIVE" AND (severity="HIGH" OR severity="CRITICAL") AND resource.project_display_name="${var.project_id}"'`.
      Until that exists the topic stays empty and this alert never fires.
    EOT
  }
}

# --- Cloud Armor -------------------------------------------------------------------------

resource "google_logging_metric" "armor_denied" {
  project     = var.project_id
  name        = "farmerapp_armor_denied"
  description = "OPS-013: requests blocked by Cloud Armor (load-balancer request log, enforcedSecurityPolicy.outcome=DENY)."
  filter      = "resource.type=\"http_load_balancer\" AND jsonPayload.enforcedSecurityPolicy.outcome=\"DENY\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "farmerapp Cloud Armor denied"

    labels {
      key        = "backend"
      value_type = "STRING"
    }
    labels {
      key        = "rule"
      value_type = "STRING"
    }
  }

  label_extractors = {
    backend = "EXTRACT(resource.labels.backend_service_name)"
    rule    = "EXTRACT(jsonPayload.enforcedSecurityPolicy.name)"
  }
}

resource "google_monitoring_alert_policy" "armor_spike" {
  count = var.security_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] Cloud Armor blocked-request spike (OPS-013, sev1)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev1

  conditions {
    display_name = "> ${var.armor_denied_per_5m} blocked requests in 5 min"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.armor_denied.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.armor_denied_per_5m
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.backend"]
      }
    }
  }

  alert_strategy {
    auto_close = "3600s"
  }

  notification_channels = local.channels.sev1
  user_labels           = merge(local.common_labels, { ops = "ops-013", owner = "platform-lead", sev = "sev1" })

  documentation {
    subject   = "[${var.env}] Cloud Armor spike"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-013: Cloud Armor blocked more than ${var.armor_denied_per_5m} requests in 5 minutes** on one backend.

      Two very different causes, and the logs tell them apart in one query:

      ```
      gcloud logging read 'resource.type="http_load_balancer" AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"' \
        --project ${var.project_id} --freshness 15m --limit 200 \
        --format='value(jsonPayload.enforcedSecurityPolicy.name, httpRequest.remoteIp, httpRequest.requestUrl)'
      ```

      * Many IPs, one rule, junk paths -> an attack; Armor is doing its job, confirm the API
        is healthy (OPS-001 / OPS-002) and leave it.
      * One rule, real paths, Indian IPs -> a rule is locking real users out. In `dev`/`stg`
        Armor is log-only, in `prd` it enforces (SPEC 9.2): move the offending rule to preview
        (`infra/modules/lb/armor.tf`) and re-apply.

      - Owner: platform lead (on-call)
      - Severity: Sev 1, page
      - Runbook: ${local.runbook.platform}
    EOT
  }
}

# --- OTP send spike (SMS pumping) --------------------------------------------------------

resource "google_monitoring_alert_policy" "otp_spike" {
  count = var.security_alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] OTP send spike, possible SMS pumping (OPS-013, sev1)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev1

  conditions {
    display_name = "> ${var.otp_sends_per_5m} SMS OTPs for one tenant in 5 min"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.counter["otp_sent"].name}\" AND metric.label.\"channel\"=\"sms\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.otp_sends_per_5m
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.tenant_id"]
      }
    }
  }

  alert_strategy {
    auto_close = "3600s"
  }

  notification_channels = local.channels.sev1
  user_labels           = merge(local.common_labels, { ops = "ops-013", owner = "platform-lead", sev = "sev1" })

  documentation {
    subject   = "[${var.env}] OTP send spike"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-013: more than ${var.otp_sends_per_5m} OTP SMS in 5 minutes for one tenant.** SMS pumping
      (an attacker cycling premium-rate numbers) costs real money per message and burns the DLT
      sender; a genuine campaign or a retry storm looks the same at first.

      1. Sends vs deliveries vs verifications: if `farmerapp_otp_sent` jumped but
         `farmerapp_otp_delivered` and logins did not, it is pumping.
      2. Number pattern: the `otp_sent` lines carry masked phones only; the `otp_challenge`
         rows carry the prefixes. A single country or series repeating is the signature.
      3. Contain: tighten the per-phone / per-IP OTP rate limits (tenant settings), and if it
         continues, block the range in Cloud Armor and switch OTP to WhatsApp-first.

      - Owner: platform lead (on-call) + finance for the spend
      - Severity: Sev 1, page
      - Runbook: ${local.runbook.otp} (provider side), ${local.runbook.cost} (the bill)
    EOT
  }
}
