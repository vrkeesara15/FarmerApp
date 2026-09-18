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
  description = "Path regex for OTP send endpoints (rate limit 5/min/IP)."
  type        = string
  default     = "^/v1/auth/otp(/send)?$"
}

variable "login_path_regex" {
  description = "Path regex for login/verify endpoints (rate limit 10/min/IP)."
  type        = string
  default     = "^/v1/auth/(login|otp/verify|refresh)$"
}

variable "india_only_path_regex" {
  description = "Path regex for farmer/agent APIs restricted to requests originating in India."
  type        = string
  default     = "^/v1/(auth|sync|farmer|agent|visits|location)"
}
