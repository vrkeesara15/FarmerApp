# Global external HTTPS load balancer in front of api and console, managed certificates,
# HTTP->HTTPS redirect, Cloud Armor (SEC-014) and optional IAP on the console (SEC-015).
#
# SEC-015: api and console run with ingress INTERNAL_LOAD_BALANCER (envs/*/main.tf), so the
# run.app URLs refuse direct traffic and every request passes this LB and its Cloud Armor
# policy. Invoker IAM is disabled on those two services instead of granting allUsers (which
# domain-restricted sharing, SEC-018, forbids); ingress is the gate.

locals {
  api_host     = "api.${var.domain}"
  console_host = "console.${var.domain}"
  preview      = var.cloud_armor_mode == "preview"
}

resource "google_compute_global_address" "lb" {
  project = var.project_id
  name    = "farmerapp-${var.env}-lb"
}

resource "google_compute_managed_ssl_certificate" "lb" {
  project = var.project_id
  name    = "farmerapp-${var.env}-cert"

  managed {
    domains = [local.api_host, local.console_host]
  }
}

resource "google_compute_region_network_endpoint_group" "api" {
  project               = var.project_id
  name                  = "farmerapp-${var.env}-api-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.api_service_name
  }
}

resource "google_compute_region_network_endpoint_group" "console" {
  project               = var.project_id
  name                  = "farmerapp-${var.env}-console-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.console_service_name
  }
}

resource "google_compute_backend_service" "api" {
  project               = var.project_id
  name                  = "farmerapp-${var.env}-api"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"
  security_policy       = var.cloud_armor_enabled ? google_compute_security_policy.armor[0].id : null

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_backend_service" "console" {
  project               = var.project_id
  name                  = "farmerapp-${var.env}-console"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"
  security_policy       = var.cloud_armor_enabled ? google_compute_security_policy.armor[0].id : null

  backend {
    group = google_compute_region_network_endpoint_group.console.id
  }

  # SEC-015 (P1): Identity-Aware Proxy in front of the console for staff SSO. Off by default;
  # uses the Google-managed OAuth client, so no client secret is stored in state.
  dynamic "iap" {
    for_each = var.console_iap_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  log_config {
    enable      = true
    sample_rate = 0.5
  }
}

resource "google_compute_url_map" "https" {
  project         = var.project_id
  name            = "farmerapp-${var.env}-https"
  default_service = google_compute_backend_service.console.id

  host_rule {
    hosts        = [local.api_host]
    path_matcher = "api"
  }

  host_rule {
    hosts        = [local.console_host]
    path_matcher = "console"
  }

  path_matcher {
    name            = "api"
    default_service = google_compute_backend_service.api.id
  }

  path_matcher {
    name            = "console"
    default_service = google_compute_backend_service.console.id
  }
}

resource "google_compute_target_https_proxy" "https" {
  project          = var.project_id
  name             = "farmerapp-${var.env}-https-proxy"
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.lb.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = "farmerapp-${var.env}-https"
  target                = google_compute_target_https_proxy.https.id
  port_range            = "443"
  ip_address            = google_compute_global_address.lb.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# HTTP → HTTPS redirect
resource "google_compute_url_map" "redirect" {
  project = var.project_id
  name    = "farmerapp-${var.env}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "farmerapp-${var.env}-http-proxy"
  url_map = google_compute_url_map.redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project               = var.project_id
  name                  = "farmerapp-${var.env}-http"
  target                = google_compute_target_http_proxy.redirect.id
  port_range            = "80"
  ip_address            = google_compute_global_address.lb.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

