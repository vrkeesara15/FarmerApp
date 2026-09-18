# VPC, one regional subnet for Cloud Run Direct VPC egress, Cloud NAT for
# egress to the internet (SMS / payment / LLM providers) and Private Service
# Access for Cloud SQL. No Serverless VPC connector: Cloud Run v2 uses
# network_interfaces (SPEC 9.5).

resource "google_compute_network" "vpc" {
  project                         = var.project_id
  name                            = "farmerapp-${var.env}"
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "run" {
  project                  = var.project_id
  name                     = "farmerapp-${var.env}-run"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = 0.1
      metadata             = "EXCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_router" "router" {
  project = var.project_id
  name    = "farmerapp-${var.env}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "farmerapp-${var.env}-nat"
  region                             = var.region
  router                             = google_compute_router.router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private Service Access range + peering for Cloud SQL private IP.
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "farmerapp-${var.env}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psa_prefix_length
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}

# Deny-all ingress baseline; Cloud Run does not need inbound firewall rules.
resource "google_compute_firewall" "deny_ingress" {
  project   = var.project_id
  name      = "farmerapp-${var.env}-deny-ingress"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 65000

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}
