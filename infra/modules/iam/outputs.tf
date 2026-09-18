output "emails" {
  description = "Service account emails keyed by short name (api, worker, jobs, console, embed, pubsub-push, scheduler)."
  value       = { for k, sa in google_service_account.sa : k => sa.email }
}

output "pubsub_service_agent" {
  description = "Pub/Sub service agent email."
  value       = google_project_service_identity.pubsub.email
}
