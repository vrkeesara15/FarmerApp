variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "region" {
  description = "Region for log buckets."
  type        = string
  default     = "asia-south1"
}

variable "notification_email" {
  description = "Email for the on-call notification channel (Sev 1/2). Empty = no channel, alerts still created."
  type        = string
  default     = ""
}

variable "extra_notification_channels" {
  description = "Existing notification channel resource names (Slack, PagerDuty) to attach to every alert."
  type        = list(string)
  default     = []
}

variable "uptime_checks" {
  description = "OPS-001: name → host + path checked every 60 s from 3 regions."
  type = map(object({
    host = string
    path = optional(string, "/healthz")
  }))
  default = {}
}

variable "sql_instance_id" {
  description = "Cloud SQL database_id (project:instance) for OPS-003 alerts. Empty = skip."
  type        = string
  default     = ""
}

variable "sql_alerts_enabled" {
  description = "Create OPS-003 Cloud SQL alerts."
  type        = bool
  default     = true
}

variable "pubsub_alerts_enabled" {
  description = "Create OPS-004 Pub/Sub alerts (oldest unacked > 10 min, any DLQ message)."
  type        = bool
  default     = true
}

variable "job_alerts_enabled" {
  description = "Create OPS-005 Cloud Run job failure alerts."
  type        = bool
  default     = true
}

variable "audit_log_retention_days" {
  description = "SEC-017: retention of the audit log bucket."
  type        = number
  default     = 400
}

variable "lock_audit_bucket" {
  description = "SEC-017: lock the audit log bucket (irreversible; true in prd)."
  type        = bool
  default     = false
}

variable "dashboard_enabled" {
  description = "Create the platform dashboard (SPEC 12.4)."
  type        = bool
  default     = true
}
