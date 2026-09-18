output "notification_channels" {
  description = "Notification channel ids attached to alerts."
  value       = local.channels
}

output "uptime_check_ids" {
  description = "Uptime check name → id."
  value       = { for k, c in google_monitoring_uptime_check_config.http : k => c.uptime_check_id }
}

output "audit_log_bucket" {
  description = "Audit log bucket id."
  value       = google_logging_project_bucket_config.audit.id
}
