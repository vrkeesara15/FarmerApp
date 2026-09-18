output "service_urls" {
  description = "Cloud Run service URLs (run.app) — internal; public traffic goes through the LB."
  value = {
    api     = module.api.uri
    console = module.console.uri
    worker  = module.worker.uri
    embed   = module.embed.uri
  }
}

output "public_urls" {
  description = "Public URLs behind the load balancer."
  value = {
    api     = module.lb.api_url
    console = module.lb.console_url
  }
}

output "lb_ip" {
  description = "Point DNS A records for api.<domain> and console.<domain> here."
  value       = module.lb.ip_address
}

output "service_account_emails" {
  description = "Per-service service accounts."
  value       = module.iam.emails
}

output "sql_connection_name" {
  description = "Cloud SQL connection name."
  value       = module.sql.connection_name
}

output "sql_replica_connection_name" {
  description = "Read replica connection name (null if none)."
  value       = module.sql.replica_connection_name
}

output "buckets" {
  description = "Bucket names."
  value       = module.storage.bucket_names
}

output "pubsub_topics" {
  description = "Topic ids."
  value       = module.pubsub.topic_ids
}

output "secret_ids" {
  description = "Secret ids to populate with `gcloud secrets versions add`."
  value       = module.secrets.secret_ids
}
