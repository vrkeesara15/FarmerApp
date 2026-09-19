output "notification_channels" {
  description = "Channel ids per severity (sev1, sev2, sev3)."
  value       = local.channels
}

output "uptime_check_ids" {
  description = "Uptime check name -> id."
  value       = { for k, c in google_monitoring_uptime_check_config.http : k => c.uptime_check_id }
}

output "audit_log_bucket" {
  description = "Audit log bucket id (SEC-017)."
  value       = google_logging_project_bucket_config.audit.id
}

output "slo_names" {
  description = "SLO resource names (for select_slo_burn_rate / dashboards)."
  value = local.slo_enabled ? merge(
    { availability = google_monitoring_slo.availability[0].name, sync = google_monitoring_slo.sync[0].name },
    { webhook = google_monitoring_slo.webhook[0].name, otp = google_monitoring_slo.otp[0].name },
    { for k, s in google_monitoring_slo.latency : "latency-${k}" => s.name },
  ) : {}
}

output "dashboards" {
  description = "Dashboard ids by name."
  value       = { for k, d in google_monitoring_dashboard.d : k => d.id }
}
