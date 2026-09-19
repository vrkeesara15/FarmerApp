variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "region" {
  description = "Region of the Cloud Run services (serverless NEGs)."
  type        = string
  default     = "asia-south1"
}

variable "domain" {
  description = "Base domain, e.g. dev.farmerapp.in. Hosts become api.<domain> and console.<domain>."
  type        = string
}

variable "api_service_name" {
  description = "Cloud Run service name for the API."
  type        = string
}

variable "console_service_name" {
  description = "Cloud Run service name for the console."
  type        = string
}

variable "cloud_armor_enabled" {
  description = "Attach a Cloud Armor policy (SEC-014). Off in dev."
  type        = bool
  default     = false
}

variable "cloud_armor_mode" {
  description = "\"preview\" = log only (stg), \"enforce\" (prd)."
  type        = string
  default     = "preview"

  validation {
    condition     = contains(["preview", "enforce"], var.cloud_armor_mode)
    error_message = "cloud_armor_mode must be preview or enforce."
  }
}

variable "otp_send_path_regex" {
  description = "Path regex of the OTP send endpoints (farmerapp/auth/router.py), rate limited per IP."
  type        = string
  default     = "^/v1/auth/(otp/send|step-up/send)$"
}

variable "otp_send_per_minute" {
  description = "SEC-014: OTP sends per minute per IP."
  type        = number
  default     = 5
}

variable "login_path_regex" {
  description = "Path regex of the login endpoints (OTP verify, step-up verify), rate limited per IP."
  type        = string
  default     = "^/v1/auth/(otp/verify|step-up)$"
}

variable "login_per_minute" {
  description = "SEC-014: login attempts per minute per IP."
  type        = number
  default     = 10
}

variable "india_only_path_regex" {
  description = "Path regex (api host) of the field-agent / farmer APIs restricted to requests from India. Excludes /v1/auth, /v1/health, /v1/webhooks and console-only resources."
  type        = string
  default     = "^/v1/(sync|duty|duty-sessions|location|visits|farmers|farms|crop-plots|uploads|blobs)(/|$)"
}

variable "console_iap_enabled" {
  description = "SEC-015 (P1): Identity-Aware Proxy in front of the console backend for staff SSO. Off by default; needs the OAuth consent screen configured once (human)."
  type        = bool
  default     = false
}

variable "console_iap_members" {
  description = "Principals allowed through IAP to the console (e.g. group:farmerapp-staff@example.com)."
  type        = list(string)
  default     = []
}
