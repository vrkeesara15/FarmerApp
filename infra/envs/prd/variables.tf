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

variable "image_registry" {
  description = "Artifact Registry prefix from bootstrap."
  type        = string
  default     = "asia-south1-docker.pkg.dev/farmerapp-ops/apps"
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
  description = "Existing notification channel resource names (Slack/PagerDuty)."
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
