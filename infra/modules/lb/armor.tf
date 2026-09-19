# --- SEC-015 (P1): IAP access to the console ------------------------------------------

resource "google_iap_web_backend_service_iam_member" "console" {
  for_each = var.console_iap_enabled ? toset(var.console_iap_members) : toset([])

  project             = var.project_id
  web_backend_service = google_compute_backend_service.console.name
  role                = "roles/iap.httpsResourceAccessor"
  member              = each.value
}

# --- Cloud Armor (SEC-014) -------------------------------------------------------------
# Mode per SPEC 9.2: off in dev, preview (log only) in stg, enforce in prd. In preview every
# rule below only records `previewSecurityPolicy` in the LB request logs.
#
# TODO(SEC-014, human gate): bot management on the OTP endpoints needs reCAPTCHA Enterprise
# keys (session / action tokens issued to the apps). Once keys exist, add
# `recaptcha_options_config { redirect_site_key = ... }` on this policy and a rule at priority
# 1900: `request.path.matches(otp_send_path_regex) && token.recaptcha_action.score < 0.5`
# -> deny(403). docs/runbooks/otp-provider-outage.md ("SMS pumping") covers the manual lever.

locals {
  waf_rules = {
    1000 = { name = "sqli", expr = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})" }
    1001 = { name = "xss", expr = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})" }
    1002 = { name = "lfi", expr = "evaluatePreconfiguredWaf('lfi-v33-stable', {'sensitivity': 1})" }
    1003 = { name = "rfi", expr = "evaluatePreconfiguredWaf('rfi-v33-stable', {'sensitivity': 1})" }
    1004 = { name = "rce", expr = "evaluatePreconfiguredWaf('rce-v33-stable', {'sensitivity': 1})" }
    1005 = { name = "scanner detection", expr = "evaluatePreconfiguredWaf('scannerdetection-v33-stable', {'sensitivity': 1})" }
    1006 = { name = "protocol attack", expr = "evaluatePreconfiguredWaf('protocolattack-v33-stable', {'sensitivity': 1})" }
  }
}

resource "google_compute_security_policy" "armor" {
  count = var.cloud_armor_enabled ? 1 : 0

  project     = var.project_id
  name        = "farmerapp-${var.env}-armor"
  description = "SEC-014 ${var.cloud_armor_mode}: OWASP CRS, OTP/login rate limits, India geo allow-list for field APIs"

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  advanced_options_config {
    json_parsing = "STANDARD" # WAF inspects JSON bodies field by field (fewer false positives)
    log_level    = local.preview ? "VERBOSE" : "NORMAL"
  }

  # OWASP ModSecurity CRS 3.3 preconfigured rules.
  dynamic "rule" {
    for_each = local.waf_rules
    content {
      action      = "deny(403)"
      priority    = rule.key
      description = "OWASP CRS: ${rule.value.name}"
      preview     = local.preview
      match {
        expr {
          expression = rule.value.expr
        }
      }
    }
  }

  # Log4Shell (CVE-2021-44228) canary: enforced in every env that has the policy, preview
  # included; it has no false positives worth tuning and CKV_GCP_73 requires it enforced.
  rule {
    action      = "deny(403)"
    priority    = 999
    description = "CVE-2021-44228 / CVE-2021-45046 Log4j canary"
    preview     = false
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('cve-canary')"
      }
    }
  }

  # Rate limits per client IP. The per-phone limit (3 / 15 min) is enforced in the API
  # (farmerapp/auth/otp.py), where the phone number is known.
  rule {
    action      = "throttle"
    priority    = 2000
    description = "OTP send: ${var.otp_send_per_minute}/min/IP"
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
        count        = var.otp_send_per_minute
        interval_sec = 60
      }
    }
  }

  rule {
    action      = "throttle"
    priority    = 2001
    description = "Login (OTP verify / step-up): ${var.login_per_minute}/min/IP"
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
        count        = var.login_per_minute
        interval_sec = 60
      }
    }
  }

  # Geo allow-list: field-agent / farmer API paths on the api host only accept requests that
  # originate in India. Not restricted: the console host, /v1/auth (staff log in from the
  # console), /v1/health (uptime checkers in EU / US) and /v1/webhooks (provider IPs).
  rule {
    action      = "deny(403)"
    priority    = 3000
    description = "Geo allow-list India for field-agent / farmer API paths"
    preview     = local.preview
    match {
      expr {
        expression = "origin.region_code != 'IN' && request.headers['host'].lower() == '${local.api_host}' && request.path.matches('${var.india_only_path_regex}')"
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
