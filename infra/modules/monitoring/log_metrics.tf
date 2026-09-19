# Log-based metrics from the structured JSON logs of the api / worker / jobs services
# (farmerapp/logging.py: structlog JSON on stdout -> Cloud Logging jsonPayload). The message
# is `jsonPayload.event`; the access log line is `event="request"` with `method`, `path`,
# `status`, `duration_ms` (farmerapp/api/middleware.py). The full field contract, and which
# events the API emits and their fields, is docs/runbooks/observability.md.
#
# Metric type in filters: logging.googleapis.com/user/<name>.

locals {
  api_logs      = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"api\""
  api_access    = "${local.api_logs} AND jsonPayload.event=\"request\" AND NOT jsonPayload.path=\"/v1/health\""
  api_or_worker = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=(\"api\" OR \"worker\")"
  any_farmerapp = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=(\"api\" OR \"worker\" OR \"console\" OR \"embed\")"

  # name -> filter + optional string labels (label -> jsonPayload field).
  counter_metrics = {
    app_errors = {
      description = "OPS-002: error-level log lines (structlog level=error/critical or Cloud Logging severity>=ERROR)."
      filter      = "${local.any_farmerapp} AND (jsonPayload.level=(\"error\" OR \"critical\") OR severity>=ERROR)"
      labels      = { event = "event" }
    }
    sync_requests = {
      description = "SLO sync success: every POST /v1/sync answered by the API."
      filter      = "${local.api_access} AND jsonPayload.path=\"/v1/sync\""
      labels      = {}
    }
    sync_success = {
      description = "SLO sync success: POST /v1/sync answered 2xx."
      filter      = "${local.api_access} AND jsonPayload.path=\"/v1/sync\" AND jsonPayload.status>=200 AND jsonPayload.status<300"
      labels      = {}
    }
    otp_sent = {
      description = "SLO OTP delivery (total): event=otp_sent (farmerapp/auth/otp.py)."
      filter      = "${local.api_logs} AND jsonPayload.event=\"otp_sent\""
      labels      = { channel = "channel", purpose = "purpose" }
    }
    otp_delivered = {
      description = "SLO OTP delivery (good): event=otp_delivered, logged by the 30 s delivery check."
      filter      = "${local.api_or_worker} AND jsonPayload.event=\"otp_delivered\""
      labels      = {}
    }
    otp_whatsapp_fallback = {
      description = "OTP fell back to WhatsApp (event=otp_fallback_whatsapp): provider-outage signal."
      filter      = "${local.api_or_worker} AND jsonPayload.event=\"otp_fallback_whatsapp\""
      labels      = {}
    }
    webhook_applied = {
      description = "Payment webhooks applied (event=webhook_applied, farmerapp/payments/webhooks.py)."
      filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"webhook_applied\""
      labels      = { status = "status" }
    }
    visits_created = {
      description = "Business ops: visits created (event=visit_created, see observability.md)."
      filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"visit_created\""
      labels      = { tenant_id = "tenant_id" }
    }
    orders_created = {
      description = "Business ops: orders created (event=order_created)."
      filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"order_created\""
      labels      = { tenant_id = "tenant_id" }
    }
    payments_captured = {
      description = "Business ops: payments captured (event=payment_captured, field mode)."
      filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"payment_captured\""
      labels      = { tenant_id = "tenant_id", mode = "mode" }
    }
    flags_raised = {
      description = "Business ops: validation flags raised (event=flag_raised, field rule_id)."
      filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"flag_raised\""
      labels      = { tenant_id = "tenant_id", rule_id = "rule_id" }
    }
  }

  # name -> filter + numeric field + explicit bucket bounds (ms or count).
  distribution_metrics = {
    api_read_latency = {
      description = "NF-005 / SLO latency: API read latency in ms (GET/HEAD access log duration_ms)."
      filter      = "${local.api_access} AND jsonPayload.method=(\"GET\" OR \"HEAD\")"
      field       = "duration_ms"
      unit        = "ms"
      bounds      = [25, 50, 100, 150, 200, 250, 300, 400, 500, 600, 800, 1000, 1500, 2000, 3000, 5000, 10000, 30000]
    }
    api_write_latency = {
      description = "NF-005 / SLO latency: API write latency in ms (POST/PUT/PATCH/DELETE access log duration_ms)."
      filter      = "${local.api_access} AND jsonPayload.method=(\"POST\" OR \"PUT\" OR \"PATCH\" OR \"DELETE\")"
      field       = "duration_ms"
      unit        = "ms"
      bounds      = [25, 50, 100, 150, 200, 250, 300, 400, 500, 600, 800, 1000, 1500, 2000, 3000, 5000, 10000, 30000]
    }
    webhook_processing = {
      description = "SLO payment webhook processing: received_at -> processed_at in ms (field processing_ms on webhook_applied)."
      filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"webhook_applied\" AND jsonPayload.processing_ms>=0"
      field       = "processing_ms"
      unit        = "ms"
      bounds      = [1000, 5000, 10000, 30000, 60000, 120000, 300000, 600000, 1800000]
    }
    officers_on_duty = {
      description = "Business ops: officers on duty now per tenant (event=ops_snapshot, field officers_on_duty)."
      filter      = "resource.type=(\"cloud_run_job\" OR \"cloud_run_revision\") AND jsonPayload.event=\"ops_snapshot\""
      field       = "officers_on_duty"
      unit        = "1"
      bounds      = [0, 1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
    }
    open_flags = {
      description = "Business ops: open validation flags per tenant (event=ops_snapshot, field open_flags)."
      filter      = "resource.type=(\"cloud_run_job\" OR \"cloud_run_revision\") AND jsonPayload.event=\"ops_snapshot\""
      field       = "open_flags"
      unit        = "1"
      bounds      = [0, 1, 10, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
    }
  }
}

resource "google_logging_metric" "counter" {
  for_each = local.counter_metrics

  project     = var.project_id
  name        = "farmerapp_${each.key}"
  description = each.value.description
  filter      = each.value.filter

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "farmerapp ${each.key}"

    dynamic "labels" {
      for_each = each.value.labels
      content {
        key        = labels.key
        value_type = "STRING"
      }
    }
  }

  label_extractors = { for k, field in each.value.labels : k => "EXTRACT(jsonPayload.${field})" }
}

resource "google_logging_metric" "distribution" {
  for_each = local.distribution_metrics

  project         = var.project_id
  name            = "farmerapp_${each.key}"
  description     = each.value.description
  filter          = each.value.filter
  value_extractor = "EXTRACT(jsonPayload.${each.value.field})"

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "DISTRIBUTION"
    unit         = each.value.unit
    display_name = "farmerapp ${each.key}"

    dynamic "labels" {
      for_each = contains(["officers_on_duty", "open_flags"], each.key) ? [1] : []
      content {
        key        = "tenant_id"
        value_type = "STRING"
      }
    }
  }

  label_extractors = contains(["officers_on_duty", "open_flags"], each.key) ? { tenant_id = "EXTRACT(jsonPayload.tenant_id)" } : {}

  bucket_options {
    explicit_buckets {
      bounds = each.value.bounds
    }
  }
}
