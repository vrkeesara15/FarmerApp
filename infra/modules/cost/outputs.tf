output "dataset_id" {
  description = "BigQuery dataset holding the billing export and the cost views."
  value       = google_bigquery_dataset.cost.dataset_id
}

output "views" {
  description = "Cost view name -> fully qualified id. Empty until the billing export is enabled."
  value       = { for k, v in google_bigquery_table.views : k => "${var.project_id}.${var.dataset_id}.${k}" }
}

output "budget_topic" {
  description = "Pub/Sub topic the NF-015 budget publishes threshold notifications to."
  value       = google_pubsub_topic.budget.name
}

output "cost_watch_service_account" {
  description = "Service account the daily cost watch runs as (null until the export is enabled)."
  value       = local.export_ready ? google_service_account.cost_watch[0].email : null
}

output "thresholds" {
  description = "The rate-card-derived alert thresholds, so docs/cost-model.md and the runbook can quote the same numbers."
  value = {
    daily_spend_ratio    = var.daily_spend_ratio
    llm_input_tokens_6h  = local.llm_input_per_6h
    llm_output_tokens_6h = local.llm_output_per_6h
    sms_messages_6h      = local.sms_per_6h
    monthly_budget_inr   = var.monthly_budget_inr
    llm_daily_inr_tenant = var.llm_daily_inr_per_tenant
    sms_daily_inr_tenant = var.sms_daily_inr_per_tenant
  }
}
