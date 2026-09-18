output "ip_address" {
  description = "Global IP to point DNS A records at (api.<domain>, console.<domain>)."
  value       = google_compute_global_address.lb.address
}

output "api_url" {
  description = "Public API base URL."
  value       = "https://${local.api_host}"
}

output "console_url" {
  description = "Public console URL."
  value       = "https://${local.console_host}"
}

output "security_policy" {
  description = "Cloud Armor policy name (null when disabled)."
  value       = var.cloud_armor_enabled ? google_compute_security_policy.armor[0].name : null
}
