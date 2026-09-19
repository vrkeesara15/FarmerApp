output "instance_name" {
  description = "Primary instance name."
  value       = google_sql_database_instance.main.name
}

output "connection_name" {
  description = "Primary instance connection name (project:region:instance)."
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip" {
  description = "Primary private IP address."
  value       = google_sql_database_instance.main.private_ip_address
}

output "database_name" {
  description = "Application database name."
  value       = google_sql_database.app.name
}

output "replica_connection_name" {
  description = "Read replica connection name (null when no replica)."
  value       = var.read_replica ? google_sql_database_instance.replica[0].connection_name : null
}

output "replica_private_ip" {
  description = "Read replica private IP (null when no replica)."
  value       = var.read_replica ? google_sql_database_instance.replica[0].private_ip_address : null
}

output "replica_instance_name" {
  description = "Read replica instance name (null when no replica)."
  value       = var.read_replica ? google_sql_database_instance.replica[0].name : null
}

output "max_connections" {
  description = "max_connections flag of the primary (connection budget, alerts)."
  value       = var.max_connections
}
