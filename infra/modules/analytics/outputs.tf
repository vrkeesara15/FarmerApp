output "raw_dataset" {
  description = "Datastream target dataset id."
  value       = google_bigquery_dataset.raw.dataset_id
}

output "marts_dataset" {
  description = "dbt marts dataset id."
  value       = google_bigquery_dataset.marts.dataset_id
}

output "views_dataset" {
  description = "Authorised views dataset id."
  value       = google_bigquery_dataset.views.dataset_id
}

output "stream_name" {
  description = "Datastream stream name (null when disabled)."
  value       = var.enabled ? google_datastream_stream.cdc[0].name : null
}
