variable "project_id" {
  description = "GCP project id for this environment."
  type        = string
}

variable "env" {
  description = "Environment name (dev | stg | prd)."
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prd"], var.env)
    error_message = "env must be dev, stg or prd."
  }
}

variable "region" {
  description = "Primary region (data residency: India)."
  type        = string
  default     = "asia-south1"
}

variable "domain" {
  description = "Base domain for this env (api.<domain>, console.<domain>)."
  type        = string
}

variable "bootstrap_image" {
  description = "Placeholder image used when a service/job is first created; CI replaces it and Terraform ignores later image changes."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

# --- Cloud SQL (SPEC 9.2) ---
variable "sql_tier" {
  description = "Cloud SQL tier."
  type        = string
  default     = "db-g1-small"
}

variable "sql_read_replica" {
  description = "Create a read replica (prd)."
  type        = bool
  default     = false
}

variable "sql_backup_location" {
  description = "Backup location (prd: asia-south2 cross-region)."
  type        = string
  default     = null
}

# --- Cloud Run ---
variable "min_instances" {
  description = "Minimum instances per service."
  type        = map(number)
  default     = { api = 0, console = 0, worker = 0, embed = 0 }
}

variable "max_instances" {
  description = "Maximum instances per service."
  type        = map(number)
  default     = { api = 20, console = 10, worker = 20, embed = 5 }
}

# --- Edge ---
variable "cloud_armor_enabled" {
  description = "Cloud Armor on the LB (off dev, on stg/prd)."
  type        = bool
  default     = false
}

variable "cloud_armor_mode" {
  description = "preview (log only, stg) | enforce (prd)."
  type        = string
  default     = "preview"
}

# --- Analytics ---
variable "datastream_enabled" {
  description = "Datastream → BigQuery (off dev, on stg/prd)."
  type        = bool
  default     = false
}

variable "datastream_password_secret_version" {
  description = "Secret version resource name holding the Datastream DB password (set out-of-band)."
  type        = string
  default     = ""
}

# --- Safety ---
variable "deletion_protection" {
  description = "Deletion protection on Cloud Run and stateful resources (off dev, on stg/prd)."
  type        = bool
  default     = false
}

# --- Monitoring ---
variable "notification_email" {
  description = "On-call notification email (OPS). Empty = no channel."
  type        = string
  default     = ""
}

variable "extra_notification_channels" {
  description = "Existing notification channel ids attached to every alert."
  type        = list(string)
  default     = []
}

variable "page_channels" {
  description = "SPEC 12.3 Sev 1 paging channel ids (PagerDuty / SMS), created by a human (they hold tokens)."
  type        = list(string)
  default     = []
}

variable "ticket_channels" {
  description = "SPEC 12.3 Sev 1 + Sev 2 channel ids (Slack #farmerapp-ops), created by a human."
  type        = list(string)
  default     = []
}

variable "digest_channels" {
  description = "SPEC 12.3 Sev 3 channel ids (daily digest)."
  type        = list(string)
  default     = []
}

variable "runbook_base_url" {
  description = "Base URL of docs/runbooks linked from every alert (set to the GitHub blob URL once the remote exists)."
  type        = string
  default     = "docs/runbooks"
}

variable "availability_goal" {
  description = "API availability SLO (NF-006: 0.995 pilot, 0.999 SaaS)."
  type        = number
  default     = 0.995
}

variable "sql_max_connections" {
  description = "Effective max_connections of the Cloud SQL primary (`SHOW max_connections`); OPS-003 alerts at 80%."
  type        = number
  default     = 100
}

# --- Jobs ---
variable "job_tenant_ids" {
  description = "Tenant ids passed as --tenant-id to the per-tenant jobs. Empty = per-tenant jobs are created but not scheduled."
  type        = list(string)
  default     = []
}

variable "location_purge_apply" {
  description = "purge-location-points runs with --apply (aggregate + drop partitions past 180 days). true only in prd; dry run elsewhere."
  type        = bool
  default     = false
}

# --- SEC-015 (P1) ---
variable "console_iap_enabled" {
  description = "Identity-Aware Proxy in front of the console for staff SSO (P1). Off by default."
  type        = bool
  default     = false
}

variable "console_iap_members" {
  description = "Principals allowed through IAP to the console (group:...)."
  type        = list(string)
  default     = []
}

variable "lock_audit_bucket" {
  description = "Lock the audit log bucket (irreversible; prd only)."
  type        = bool
  default     = false
}

variable "cors_origins" {
  description = "Allowed browser origins for signed-URL uploads to the photos bucket."
  type        = list(string)
  default     = []
}

# --- M6 diagnosis engine (DX-002 / DX-004, OPS-009) ---
variable "diagnosis_encoder_name" {
  description = "DX-005 pinned encoder served by `embed` (DIAGNOSIS_ENCODER_NAME). Changing it = full corpus re-embedding (DX-012)."
  type        = string
  default     = "siglip-base-patch16-224"
}

variable "diagnosis_encoder_version" {
  description = "DX-005 pinned encoder weights version (DIAGNOSIS_ENCODER_VERSION)."
  type        = string
  default     = "2024-01"
}

variable "diagnosis_llm" {
  description = "DX-004 LLM fallback: claude (needs a version in the anthropic-api-key secret) or off (every fallback goes to the agronomist queue). fake is never deployed."
  type        = string
  default     = "claude"

  validation {
    condition     = contains(["claude", "off"], var.diagnosis_llm)
    error_message = "The diagnosis_llm value must be claude or off."
  }
}

variable "diagnosis_llm_model" {
  description = "DX-004 model id (DIAGNOSIS_LLM_MODEL)."
  type        = string
  default     = "claude-opus-5"
}

variable "diagnosis_alerts_enabled" {
  description = "OPS-009 log-based alerts: review queue older than 18 h, LLM fallback rate > 40 % in a day."
  type        = bool
  default     = true
}

# --- App settings (docs/deploy/configuration.md) ---
variable "log_level" {
  description = "LOG_LEVEL of api / worker / jobs / migrate."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "The log_level value must be DEBUG, INFO, WARNING or ERROR."
  }
}

variable "otel_sample_ratio" {
  description = "NF-014 OTEL_SAMPLE_RATIO: head sampling of new traces (Cloud Trace)."
  type        = number
  default     = 1.0

  validation {
    condition     = var.otel_sample_ratio >= 0 && var.otel_sample_ratio <= 1
    error_message = "The otel_sample_ratio value must be between 0 and 1."
  }
}

variable "razorpay_base_url" {
  description = "RAZORPAY_BASE_URL (FA-021). The same host serves test and live mode; the key pair in Secret Manager decides (test keys outside prd)."
  type        = string
  default     = "https://api.razorpay.com"

  validation {
    condition     = startswith(var.razorpay_base_url, "https://")
    error_message = "The razorpay_base_url value must be an https URL (the local mockserver is never deployed)."
  }
}
