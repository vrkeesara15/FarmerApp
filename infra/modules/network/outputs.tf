output "vpc_id" {
  description = "Self link id of the VPC (for Cloud SQL private_network)."
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "VPC name (for Cloud Run network_interfaces)."
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Cloud Run egress subnet name."
  value       = google_compute_subnetwork.run.name
}

output "subnet_id" {
  description = "Cloud Run egress subnet id."
  value       = google_compute_subnetwork.run.id
}

output "psa_connection" {
  description = "Private Service Access connection (depend on this before creating Cloud SQL)."
  value       = google_service_networking_connection.psa.id
}

output "datastream_subnet_cidr" {
  description = "Reserved /29 for the Datastream private connection."
  value       = var.datastream_subnet_cidr
}
