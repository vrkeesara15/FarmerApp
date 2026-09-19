output "raw_dataset" {
  description = "Datastream target dataset id."
  value       = google_bigquery_dataset.raw.dataset_id
}

output "staging_dataset" {
  description = "dbt staging dataset id."
  value       = google_bigquery_dataset.staging.dataset_id
}

output "marts_dataset" {
  description = "dbt marts dataset id."
  value       = google_bigquery_dataset.marts.dataset_id
}

output "views_dataset" {
  description = "Authorised views dataset id (the only dataset the BI reader can read)."
  value       = google_bigquery_dataset.views.dataset_id
}

output "dbt_service_account" {
  description = "Service account dbt runs as (DBT_IMPERSONATE_SA / ci-dbt.yml DBT_SA_DEV)."
  value       = google_service_account.dbt.email
}

output "reader_service_account" {
  description = "Service account the console reads the authorised views as."
  value       = google_service_account.reader.email
}

output "datastream_service_agent" {
  description = "Datastream service agent (needs secretAccessor on the password secret)."
  value       = local.datastream_agent
}

output "replicated_tables" {
  description = "Tables in the Datastream column allowlist."
  value       = sort(keys(local.replicated))
}

output "stream_name" {
  description = "Datastream stream name (null until datastream_stream_enabled)."
  value       = local.stream == 1 ? google_datastream_stream.cdc[0].name : null
}
