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

# --- channels (SPEC 12.3) ---

variable "notification_email" {
  description = "On-call e-mail; attached to every severity. Empty = no e-mail channel (alerts are still created)."
  type        = string
  default     = ""
}

variable "page_channels" {
  description = "Sev 1 paging channel ids (PagerDuty / SMS / phone), created by a human because they hold tokens."
  type        = list(string)
  default     = []
}

variable "ticket_channels" {
  description = "Sev 1 + Sev 2 channel ids (Slack #farmerapp-ops), created by a human."
  type        = list(string)
  default     = []
}

variable "digest_channels" {
  description = "Sev 3 channel ids (daily digest to owners)."
  type        = list(string)
  default     = []
}

variable "extra_notification_channels" {
  description = "Channel ids attached to every alert regardless of severity (kept for compatibility)."
  type        = list(string)
  default     = []
}

variable "runbook_base_url" {
  description = "Base URL of docs/runbooks, linked from every alert's documentation (e.g. https://github.com/<org>/farmerapp/blob/main/docs/runbooks)."
  type        = string
  default     = "docs/runbooks"
}

# --- OPS-001 ---

variable "uptime_checks" {
  description = "OPS-001: name -> host + path, checked every 60 s from uptime_regions. accepted_status = a single status code instead of 2xx (the webhook answers GET with 405)."
  type = map(object({
    host            = string
    path            = optional(string, "/v1/health")
    accepted_status = optional(number)
  }))
  default = {}
}

variable "uptime_regions" {
  description = "OPS-001: at least three checker regions."
  type        = list(string)
  default     = ["ASIA_PACIFIC", "EUROPE", "USA_OREGON"]

  validation {
    condition     = length(var.uptime_regions) >= 3
    error_message = "OPS-001 needs uptime checks from at least three regions."
  }
}

# --- OPS-002 ---

variable "error_rate_alerts_enabled" {
  description = "Create OPS-002 error-rate alerts."
  type        = bool
  default     = true
}

variable "error_rate_services" {
  description = "Cloud Run services with a 5xx-ratio alert."
  type        = list(string)
  default     = ["api", "console", "worker"]
}

variable "error_rate_threshold" {
  description = "5xx / all requests ratio that fires OPS-002 (0.02 = 2%) over 10 min."
  type        = number
  default     = 0.02
}

variable "app_error_burst_per_5m" {
  description = "Error-level log lines per service in 5 min that fire the error-burst alert."
  type        = number
  default     = 20
}

# --- OPS-003 ---

variable "sql_alerts_enabled" {
  description = "Create OPS-003 Cloud SQL alerts."
  type        = bool
  default     = true
}

variable "sql_instance_id" {
  description = "Cloud SQL database_id (project:instance) of the primary for OPS-003. Empty = skip."
  type        = string
  default     = ""
}

variable "sql_replica_instance_id" {
  description = "Cloud SQL database_id (project:instance) of the read replica (prd) for the replication-lag alert. Empty = skip."
  type        = string
  default     = ""
}

variable "sql_max_connections" {
  description = "Effective max_connections of the primary (`SHOW max_connections`); the connections alert fires at 80% of it."
  type        = number
  default     = 100
}

# --- OPS-004 ---

variable "pubsub_alerts_enabled" {
  description = "Create OPS-004 Pub/Sub alerts."
  type        = bool
  default     = true
}

variable "pubsub_topics" {
  description = "Topics created by modules/pubsub; alerts watch <topic>.worker (age) and <topic>.dlq.replay (any message)."
  type        = list(string)
  default     = []
}

variable "sev1_topics" {
  description = "Topics whose backlog / dead letters are Sev 1 (payment failure)."
  type        = list(string)
  default     = ["payment.webhook"]
}

# --- OPS-005 ---

variable "job_alerts_enabled" {
  description = "Create OPS-005 Cloud Run job failure alerts."
  type        = bool
  default     = true
}

variable "jobs" {
  description = "OPS-005: Cloud Run job name -> owner (label-safe, e.g. platform-lead) and what it does."
  type = map(object({
    owner       = string
    description = string
  }))
  default = {}
}

# --- SLOs (12.1) ---

variable "slo_enabled" {
  description = "Create the SPEC 12.1 SLOs and their alerts on the api service."
  type        = bool
  default     = true
}

variable "api_service_name" {
  description = "Cloud Run service name of the API."
  type        = string
  default     = "api"
}

variable "availability_goal" {
  description = "API availability SLO (NF-006: 0.995 pilot, 0.999 SaaS)."
  type        = number
  default     = 0.995
}

# --- SEC-017 ---

variable "audit_services" {
  description = "SEC-017: services with Data Access audit logs (ADMIN_READ, DATA_READ, DATA_WRITE)."
  type        = list(string)
  default     = ["sqladmin.googleapis.com", "secretmanager.googleapis.com", "storage.googleapis.com"]
}

variable "audit_log_retention_days" {
  description = "SEC-017: retention of the audit log bucket."
  type        = number
  default     = 400
}

variable "lock_audit_bucket" {
  description = "SEC-017: lock the audit log bucket (irreversible; true in prd only)."
  type        = bool
  default     = false
}

# --- 12.4 ---

variable "dashboard_enabled" {
  description = "Create the SPEC 12.4 dashboards (platform, business ops, cost placeholder)."
  type        = bool
  default     = true
}
