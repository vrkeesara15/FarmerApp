# OPS-012 alert policies. SPEC 12.2's action is "Notify owner + platform lead", i.e. a
# ticket, not a page: nothing here is an outage, and paging someone at 03:00 about a bill
# trains them to ignore pages. All four are Sev 2 (ticket channels + e-mail).
#
#   daily anomaly   the cost-watch scheduled query failed (main.tf): either a day is above
#                   ${var.daily_spend_ratio}x the trailing 7-day average, or the query
#                   itself broke. Both need the same person to open the same table.
#   LLM per tenant  from `farmerapp_llm_input_tokens` / `_output_tokens` (log-based, per
#                   tenant, per model), converted with the rate card. Two conditions rather
#                   than one sum because input and output are priced differently and
#                   Monitoring cannot add two metrics inside one condition.
#   SMS per tenant  from `farmerapp_otp_sent{channel="sms"}`, converted the same way.
#   budget          the NF-015 monthly budget crossed a threshold (forecast or actual).
#
# The LLM and SMS conditions are evaluated over a 6-hour window against a quarter of the
# daily budget, so a runaway is caught the same morning instead of the next one. A steady
# tenant that simply uses a lot is visible on the cost dashboard long before it alerts.

locals {
  cost_runbook = "${var.runbook_base_url}/cost-and-budget.md"

  # A 6-hour window is a quarter of a day's budget.
  window_seconds    = 21600
  window_fraction   = 4
  llm_input_per_6h  = ceil(var.llm_daily_inr_per_tenant / local.window_fraction / var.llm_input_inr_per_1k_tokens * 1000)
  llm_output_per_6h = ceil(var.llm_daily_inr_per_tenant / local.window_fraction / var.llm_output_inr_per_1k_tokens * 1000)
  sms_per_6h        = ceil(var.sms_daily_inr_per_tenant / local.window_fraction / var.sms_inr_per_message)
  cost_watch_config = local.export_ready ? element(split("/", google_bigquery_data_transfer_config.cost_watch[0].name), length(split("/", google_bigquery_data_transfer_config.cost_watch[0].name)) - 1) : ""
  cost_labels       = merge(local.labels, { ops = "ops-012", owner = "product-owner", sev = "sev2" })
}

resource "google_monitoring_alert_policy" "cost_watch_failed" {
  count = var.alerts_enabled && local.export_ready ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] daily spend above ${var.daily_spend_ratio * 100}% of the 7-day average (OPS-012, sev2)"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "cost-watch scheduled query failed"
    condition_threshold {
      filter          = "metric.type=\"bigquerydatatransfer.googleapis.com/transfer_config/completed_transfer_run_count\" AND resource.type=\"bigquery_dts_config\" AND resource.label.\"config_id\"=\"${local.cost_watch_config}\" AND metric.label.\"run_status\"=\"FAILED\""
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
    auto_close = "172800s"
  }

  notification_channels = var.notification_channels.sev2
  user_labels           = local.cost_labels

  documentation {
    subject   = "[${var.env}] daily cost anomaly"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-012: the daily cost watch did not come back clean.** Either a day's net spend was
      above ${var.daily_spend_ratio * 100}% of the average of the seven days before it, or the query itself failed.

      Start with the table it writes -- it says which:

      ```sql
      SELECT * FROM `${var.project_id}.${var.dataset_id}.cost_watch_daily`
      ORDER BY checked_at DESC LIMIT 20;
      ```

      Then find the service and the SKU that moved:

      ```sql
      SELECT day, service, component, ROUND(net_cost, 2) AS inr
      FROM `${var.project_id}.${var.dataset_id}.v_cost_daily_by_service`
      WHERE day >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 10 DAY)
      ORDER BY day DESC, inr DESC;
      ```

      A legitimate jump (a backfill, a load test, a new environment) is closed with a note.
      A jump nobody ordered is a runaway: the usual four are Cloud Run min-instances left
      high after a load test, a Datastream backfill, log volume after a debug deploy, and a
      BigQuery query without a partition filter.

      - Owner: product owner (the budget) + platform lead (the cause)
      - Severity: Sev 2, ticket
      - Runbook: ${local.cost_runbook}
    EOT
  }
}

resource "google_monitoring_alert_policy" "llm_spend_tenant" {
  count = var.alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] LLM spend above Rs ${var.llm_daily_inr_per_tenant}/day for one tenant (OPS-012, sev2)"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "> ${local.llm_input_per_6h} input tokens in 6 h for one tenant"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/farmerapp_llm_input_tokens\""
      comparison      = "COMPARISON_GT"
      threshold_value = local.llm_input_per_6h
      duration        = "0s"
      aggregations {
        alignment_period     = "${local.window_seconds}s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.tenant_id"]
      }
    }
  }

  conditions {
    display_name = "> ${local.llm_output_per_6h} output tokens in 6 h for one tenant"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/farmerapp_llm_output_tokens\""
      comparison      = "COMPARISON_GT"
      threshold_value = local.llm_output_per_6h
      duration        = "0s"
      aggregations {
        alignment_period     = "${local.window_seconds}s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.tenant_id"]
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = var.notification_channels.sev2
  user_labels           = local.cost_labels

  documentation {
    subject   = "[${var.env}] LLM spend for one tenant"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-012: one tenant's LLM fallback spend is on course to pass Rs ${var.llm_daily_inr_per_tenant} today.**
      Threshold in tokens (rate card: Rs ${var.llm_input_inr_per_1k_tokens} / 1k input, Rs ${var.llm_output_inr_per_1k_tokens} / 1k output, a quarter of the
      daily budget per 6-hour window): ${local.llm_input_per_6h} input or ${local.llm_output_per_6h} output tokens.

      The LLM is the *fallback* path of the diagnosis pipeline: high spend means the corpus is
      not answering. Check the OPS-009 LLM-fallback-rate alert first -- if the fallback rate
      also jumped, fix the cause (corpus gap, encoder regression) rather than the bill.

      Immediate lever: `diagnosis_llm = "off"` (Terraform `DIAGNOSIS_LLM=off`) sends every
      fallback straight to the agronomist review queue and spend stops. That queue then grows,
      so it is a stop-gap, not a fix.

      - Owner: product owner + agronomist lead
      - Severity: Sev 2, ticket
      - Runbook: ${local.cost_runbook}, ${var.runbook_base_url}/observability.md#ops-009-diagnosis-review-queue-and-llm-fallback
    EOT
  }
}

resource "google_monitoring_alert_policy" "sms_spend_tenant" {
  count = var.alerts_enabled ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] SMS spend above Rs ${var.sms_daily_inr_per_tenant}/day for one tenant (OPS-012, sev2)"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "> ${local.sms_per_6h} SMS in 6 h for one tenant"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/farmerapp_otp_sent\" AND metric.label.\"channel\"=\"sms\""
      comparison      = "COMPARISON_GT"
      threshold_value = local.sms_per_6h
      duration        = "0s"
      aggregations {
        alignment_period     = "${local.window_seconds}s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.tenant_id"]
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = var.notification_channels.sev2
  user_labels           = local.cost_labels

  documentation {
    subject   = "[${var.env}] SMS spend for one tenant"
    mime_type = "text/markdown"
    content   = <<-EOT
      **OPS-012: one tenant sent more than ${local.sms_per_6h} OTP SMS in 6 hours**, about Rs ${var.sms_daily_inr_per_tenant} a day at
      Rs ${var.sms_inr_per_message} per message.

      This is the *cost* view of the same signal OPS-013 pages on at a much higher rate. Below
      the paging threshold the usual causes are dull: a campaign, a re-onboarding drive, or an
      app version retrying OTP sends. Check sends vs verifications -- sends without logins are
      either pumping (OPS-013) or a broken client.

      - Owner: product owner + platform lead
      - Severity: Sev 2, ticket
      - Runbook: ${local.cost_runbook}, ${var.runbook_base_url}/otp-provider-outage.md
    EOT
  }
}

resource "google_monitoring_alert_policy" "budget_threshold" {
  count = var.alerts_enabled && var.billing_account != "" && var.monthly_budget_inr > 0 ? 1 : 0

  project      = var.project_id
  display_name = "[${var.env}] monthly budget threshold crossed (NF-015 / OPS-012, sev2)"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "a budget notification was published to ${var.budget_topic}"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/topic/send_request_count\" AND resource.type=\"pubsub_topic\" AND resource.label.\"topic_id\"=\"${var.budget_topic}\""
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
    auto_close = "172800s"
  }

  notification_channels = var.notification_channels.sev2
  user_labels           = merge(local.cost_labels, { nf = "nf-015" })

  documentation {
    subject   = "[${var.env}] monthly budget"
    mime_type = "text/markdown"
    content   = <<-EOT
      **NF-015: month-to-date (or forecast) spend crossed a threshold of the Rs ${var.monthly_budget_inr} monthly budget**
      for `${var.project_id}`.

      The budget publishes every threshold in `${var.budget_topic}`, so this fires at 50%,
      90%, 100% and ${var.daily_spend_ratio * 100}% as well as on the forecast. Which one it is
      is in the message; the month's shape is in

      ```sql
      SELECT * FROM `${var.project_id}.${var.dataset_id}.v_cost_monthly_vs_budget` ORDER BY invoice_month DESC;
      ```

      The levers, cheapest first, are in docs/cost-model.md: Cloud Run min-instances, log
      retention and exclusions, Datastream table allowlist, BigQuery partition filters and
      slot reservations, Cloud SQL tier and the read replica.

      - Owner: product owner (decision) + platform lead (levers)
      - Severity: Sev 2, ticket
      - Runbook: ${local.cost_runbook}
    EOT
  }
}
