# SPEC 12: monitoring, alerting and operational workflows, all in Terraform.
#
#   main.tf         notification routing by severity (12.3) + shared locals
#   uptime.tf       OPS-001 uptime checks (3 regions) and their page alerts
#   alerts.tf       OPS-002 error rate, OPS-003 Cloud SQL, OPS-004 Pub/Sub, OPS-005 jobs
#   log_metrics.tf  log-based metrics from the API's structured JSON logs (SLIs, business ops)
#   slo.tf          12.1 SLOs on the api service + burn-rate / latency alerts
#   dashboards.tf   12.4 platform, business ops and cost dashboards
#   audit.tf        SEC-017 Data Access audit logs -> locked 400-day log bucket
#   diagnosis.tf    OPS-009 diagnosis review queue age and LLM fallback rate (log-based)
#
# Every alert policy carries (SPEC 12: "every alert has an owner, a severity and a runbook
# link"): user_labels {ops, owner, sev}, the Cloud Monitoring severity, and a documentation
# block naming owner, severity and the runbook URL.
#
# Severity -> channels (SPEC 12.3):
#   sev1 (outage, payment failure, data leak) -> page_channels + ticket_channels (+ email)
#   sev2 (degraded, job failure)              -> ticket_channels (+ email)
#   sev3 (business signals, data quality)     -> digest_channels (+ email)
# Slack / PagerDuty / SMS channels hold tokens, so a human creates them and passes the ids;
# only the e-mail channel is created here (no secrets in state).

locals {
  email_channel = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  channels = {
    sev1 = distinct(concat(local.email_channel, var.page_channels, var.ticket_channels, var.extra_notification_channels))
    sev2 = distinct(concat(local.email_channel, var.ticket_channels, var.extra_notification_channels))
    sev3 = distinct(concat(local.email_channel, var.digest_channels, var.extra_notification_channels))
  }

  # Cloud Monitoring's own severity field (incident list, filters).
  gcp_severity = { sev1 = "CRITICAL", sev2 = "ERROR", sev3 = "WARNING" }

  common_labels = { app = "farmerapp", env = var.env }

  runbook = {
    index    = "${var.runbook_base_url}/README.md"
    platform = "${var.runbook_base_url}/platform-incident.md"
    otp      = "${var.runbook_base_url}/otp-provider-outage.md"
    webhook  = "${var.runbook_base_url}/payment-webhook-backlog.md"
    sql      = "${var.runbook_base_url}/cloud-sql-failover-restore.md"
    dr       = "${var.runbook_base_url}/disaster-recovery.md"
    mobile   = "${var.runbook_base_url}/bad-mobile-release-rollback.md"
    location = "${var.runbook_base_url}/mass-location-anomaly.md"
    jobs     = "${var.runbook_base_url}/job-failure.md"
    breach   = "${var.runbook_base_url}/suspected-data-breach.md"
    # OPS-009 steps live in the observability runbook (section anchor).
    diagnosis = "${var.runbook_base_url}/observability.md#ops-009-diagnosis-review-queue-and-llm-fallback"
  }
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
