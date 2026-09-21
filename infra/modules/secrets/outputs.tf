output "secret_ids" {
  description = "Secret ids keyed by name (use in run_service secret_env)."
  value       = { for k, s in google_secret_manager_secret.s : k => s.secret_id }
}

output "secret_names" {
  description = "Full resource names (projects/<n>/secrets/<id>)."
  value       = { for k, s in google_secret_manager_secret.s : k => s.name }
}

output "rotation_topic" {
  description = "OPS-014: Pub/Sub topic Secret Manager publishes 90-day rotation reminders to (null when rotation is off)."
  value       = local.rotate ? google_pubsub_topic.rotation[0].name : null
}
