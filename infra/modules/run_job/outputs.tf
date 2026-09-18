output "name" {
  description = "Job name."
  value       = google_cloud_run_v2_job.job.name
}

output "id" {
  description = "Job id."
  value       = google_cloud_run_v2_job.job.id
}

output "scheduler_job" {
  description = "Cloud Scheduler job name (null when unscheduled)."
  value       = var.schedule != "" ? google_cloud_scheduler_job.trigger[0].name : null
}
