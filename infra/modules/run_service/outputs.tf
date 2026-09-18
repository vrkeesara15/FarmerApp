output "name" {
  description = "Service name."
  value       = google_cloud_run_v2_service.svc.name
}

output "uri" {
  description = "Service URL (run.app)."
  value       = google_cloud_run_v2_service.svc.uri
}

output "id" {
  description = "Service id."
  value       = google_cloud_run_v2_service.svc.id
}
