# OPS-014 (SPEC 12.2): "Certificate expiry < 21 days; secret age > 90 days -> ticket".
#
# Neither needs a scheduled job of our own:
#
#   certificates  the OPS-001 uptime checks already run `validate_ssl` against the public
#                 load balancer every 60 s from three regions, and Cloud Monitoring exports
#                 `uptime_check/time_until_ssl_cert_expires` (days) from them. One alert per
#                 checked host at 21 days. Google-managed certificates renew themselves ~30
#                 days out, so this firing means the renewal is stuck (usually the domain's
#                 DNS no longer points at the LB) -- which is exactly the ticket we want.
#   secrets       modules/secrets sets `rotation_period = 90 days` on every secret and owns
#                 the rotation topic (it also grants the Secret Manager service agent publish
#                 on it, without which `secrets create` with a rotation is rejected). Secret
#                 Manager then publishes a `SECRET_ROTATE` message when a secret reaches 90
#                 days. A message on the topic *is* "secret age > 90 days", so the alert is
#                 "anything published". No polling, no job, and the reminder survives
#                 Terraform being idle. Only the topic *name* is shared with this module, so
#                 there is no resource edge between monitoring and secrets (monitoring
#                 already depends on the jobs, which depend on the secrets).
#
# Both are Sev 2 (ticket) per SPEC 12.2. An expired certificate becomes Sev 1 on its own
# through OPS-001 (every uptime check fails at once).

# --- certificate expiry ------------------------------------------------------------------

resource "google_monitoring_alert_policy" "cert_expiry" {
  for_each = var.cert_secret_alerts_enabled ? var.uptime_checks : {}

  project      = var.project_id
  display_name = "[${var.env}] ${each.key} certificate expires in < ${var.cert_expiry_days} days (OPS-014, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "time_until_ssl_cert_expires < ${var.cert_expiry_days} days"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/time_until_ssl_cert_expires\" AND resource.type=\"uptime_url\" AND metric.label.\"check_id\"=\"${google_monitoring_uptime_check_config.http[each.key].uptime_check_id}\""
      comparison      = "COMPARISON_LT"
      threshold_value = var.cert_expiry_days
      duration        = "3600s"
      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_MIN"
        cross_series_reducer = "REDUCE_MIN"
        group_by_fields      = ["resource.label.host"]
      }
    }
  }

  alert_strategy {
    auto_close = "604800s"
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-014", owner = "platform-lead", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] ${each.key} certificate expiry"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-014: the TLS certificate for `${each.value.host}` expires in less than ${var.cert_expiry_days} days.**

      ```
      gcloud compute ssl-certificates list --project ${var.project_id} --format='table(name,type,managed.status,managed.domainStatus,expireTime)'
      ```

      Google-managed certificates renew about 30 days out, so a `PROVISIONING` /
      `FAILED_NOT_VISIBLE` domain status is the usual cause: the A record for
      `${each.value.host}` must point at the load balancer's IP for the renewal to complete.
      Also check the apps' pinned certificates (SEC-009, `API_CERT_PINS`): a new leaf needs a
      matching pin **shipped in an app release first**, so start that release now, not at
      expiry.

      - Owner: platform lead
      - Severity: Sev 2, ticket (it becomes Sev 1 through OPS-001 when it actually expires)
      - Runbook: ${local.runbook.platform}
    EOT
  }
}

# --- secret age --------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "secret_age" {
  count = var.cert_secret_alerts_enabled && var.secret_rotation_topic != "" ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] secret older than ${var.secret_max_age_days} days (OPS-014, sev2)"
  combiner     = "OR"
  severity     = local.gcp_severity.sev2

  conditions {
    display_name = "a rotation reminder was published to ${var.secret_rotation_topic}"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/topic/send_request_count\" AND resource.type=\"pubsub_topic\" AND resource.label.\"topic_id\"=\"${var.secret_rotation_topic}\""
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
    auto_close = "604800s"
  }

  notification_channels = local.channels.sev2
  user_labels           = merge(local.common_labels, { ops = "ops-014", owner = "platform-lead", sev = "sev2" })

  documentation {
    subject   = "[${var.env}] secret rotation due"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-014 / SEC-013: a Secret Manager secret has reached ${var.secret_max_age_days} days** and is due for rotation.
      The message names the secret; the same list, with ages, is:

      ```
      gcloud secrets versions list <secret> --project ${var.project_id} --format='table(name,state,createTime)'
      ```

      Rotating is always "add a new version, move the consumers, disable the old one" --
      never destroy the old version in the same step, or an in-flight revision loses its
      credential. `latest` is resolved at container start, so Cloud Run services need a new
      revision (`gcloud run services update <svc> --update-secrets=...` or a redeploy) before
      the old version is disabled.

      Creating or rotating a **real** secret value is a human-only action (CLAUDE.md): Claude
      never runs `gcloud secrets versions add` against dev, stg or prd.

      - Owner: platform lead (the secret's owner for provider credentials)
      - Severity: Sev 2, ticket
      - Runbook: ${local.runbook.platform}
    EOT
  }
}
