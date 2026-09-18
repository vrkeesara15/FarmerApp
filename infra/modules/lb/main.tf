# Global external HTTPS load balancer in front of api and console
# (Cloud Run ingress = INTERNAL_LOAD_BALANCER, SEC-015), managed certificates,
# HTTP→HTTPS redirect and an optional Cloud Armor policy (SEC-014).

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

# --- Cloud Armor (SEC-014) -------------------------------------------------
# preview = true logs what would have been blocked without enforcing (stg).
# TODO(SEC-014): bot management on OTP endpoints needs reCAPTCHA Enterprise
# keys; add a redirect/challenge rule once the keys exist.

resource "google_compute_security_policy" "armor" {
  count = var.cloud_armor_enabled ? 1 : 0

  project     = var.project_id
  name        = "farmerapp-${var.env}-armor"
  description = "OWASP CRS, rate limits and India geo allow-list for FarmerApp ${var.env}"

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  # OWASP CRS preconfigured WAF rules
  rule {
    action      = "deny(403)"
    priority    = 1000
    description = "OWASP: SQL injection"
    preview     = local.preview
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1001
    description = "OWASP: XSS"
    preview     = local.preview
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 1002
    description = "OWASP: LFI / RFI / RCE"
    preview     = local.preview
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('lfi-v33-stable', {'sensitivity': 1}) || evaluatePreconfiguredWaf('rfi-v33-stable', {'sensitivity': 1}) || evaluatePreconfiguredWaf('rce-v33-stable', {'sensitivity': 1})"
      }
    }
  }

  # Rate limits: OTP send 5/min/IP, login 10/min/IP. (3 / 15 min / phone is enforced in the API.)
  rule {
    action      = "throttle"
    priority    = 2000
    description = "Rate limit OTP send: 5/min/IP"
    preview     = local.preview
    match {
      expr {
        expression = "request.path.matches('${var.otp_send_path_regex}')"
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 5
        interval_sec = 60
      }
    }
  }

  rule {
    action      = "throttle"
    priority    = 2001
    description = "Rate limit login: 10/min/IP"
    preview     = local.preview
    match {
      expr {
        expression = "request.path.matches('${var.login_path_regex}')"
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 10
        interval_sec = 60
      }
    }
  }

  # Geo allow-list: farmer/agent APIs only from India.
  rule {
    action      = "deny(403)"
    priority    = 3000
    description = "Geo allow-list India for farmer/agent APIs"
    preview     = local.preview
    match {
      expr {
        expression = "origin.region_code != 'IN' && request.path.matches('${var.india_only_path_regex}')"
      }
    }
  }

  rule {
    action      = "allow"
    priority    = 2147483647
    description = "default allow"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
