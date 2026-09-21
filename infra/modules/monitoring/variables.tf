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

# --- OPS-009 ---

variable "diagnosis_alerts_enabled" {
  description = "Create the OPS-009 diagnosis alerts (review queue age, LLM fallback rate)."
  type        = bool
  default     = true
}

variable "diagnosis_queue_age_hours" {
  description = "OPS-009 / DX-006: alert when the oldest diagnosis in the review queue is older than this (hours)."
  type        = number
  default     = 18
}

variable "diagnosis_llm_rate_percent" {
  description = "OPS-009: LLM fallback share of a day's answers that the job alerts on (documentation; the job applies it)."
  type        = number
  default     = 40
}

# --- 12.4 ---

variable "dashboard_enabled" {
  description = "Create the SPEC 12.4 dashboards (platform, business ops, cost)."
  type        = bool
  default     = true
}

# --- OPS-011 (data) ---

variable "data_alerts_enabled" {
  description = "Create the OPS-011 data alerts (Datastream lag, dbt run / test failure, dbt source freshness)."
  type        = bool
  default     = true
}

variable "datastream_stream_ids" {
  description = "OPS-011: Datastream stream ids to watch (modules/analytics `stream_name`, last path segment). Empty = no Datastream alerts (dev before the stream exists)."
  type        = list(string)
  default     = []
}

variable "datastream_lag_minutes" {
  description = "OPS-011: alert when a stream's freshness exceeds this many minutes (SPEC 12.2: 30)."
  type        = number
  default     = 30

  validation {
    condition     = var.datastream_lag_minutes > 0 && var.datastream_lag_minutes <= 30
    error_message = "SPEC 12.2 caps the Datastream lag alert at 30 minutes."
  }
}

variable "data_freshness_error_minutes" {
  description = "AN-010 / OPS-011: the dbt source-freshness error threshold, for the alert text (dbt applies it; dbt/models/staging/_sources.yml)."
  type        = number
  default     = 30
}

# --- OPS-013 (security) ---

variable "security_alerts_enabled" {
  description = "Create the OPS-013 security alerts (SCC high findings, Cloud Armor spikes, OTP send spikes)."
  type        = bool
  default     = true
}

variable "scc_findings_topic" {
  description = "OPS-013: Pub/Sub topic that receives Security Command Center HIGH / CRITICAL findings. Terraform creates the topic; pointing SCC at it is an org-level human gate."
  type        = string
  default     = "scc.findings"
}

variable "scc_organization_id" {
  description = "OPS-013: organisation id, used only to grant publish on the findings topic to the SCC notification service agent. Empty = skip the binding (the org owner grants it by hand)."
  type        = string
  default     = ""
}

variable "armor_denied_per_5m" {
  description = "OPS-013: Cloud Armor DENY responses in 5 minutes that page on-call."
  type        = number
  default     = 500
}

variable "otp_sends_per_5m" {
  description = "OPS-013: SMS OTPs sent for one tenant in 5 minutes that page on-call (SMS pumping)."
  type        = number
  default     = 300
}

# --- OPS-014 (certificates and secrets) ---

variable "cert_secret_alerts_enabled" {
  description = "Create the OPS-014 alerts (certificate expiry, secret age)."
  type        = bool
  default     = true
}

variable "cert_expiry_days" {
  description = "OPS-014: ticket when a load-balancer certificate expires in fewer than this many days (SPEC 12.2: 21)."
  type        = number
  default     = 21
}

variable "secret_rotation_topic" {
  description = "OPS-014 / SEC-013: Pub/Sub topic Secret Manager publishes rotation reminders to (modules/secrets `rotation_topic`). Empty = no secret-age alert."
  type        = string
  default     = "secret.rotation"
}

variable "secret_max_age_days" {
  description = "OPS-014 / SEC-013: secret age that raises a ticket, for the alert text (modules/secrets `rotation_days` applies it)."
  type        = number
  default     = 90
}

# --- OPS-012 / NF-015 (cost dashboard) ---

variable "cost_dataset" {
  description = "NF-015 / OPS-012: BigQuery dataset holding the billing export and the cost views (modules/cost), linked from the cost dashboard. Empty = the dashboard shows usage drivers only."
  type        = string
  default     = ""
}

variable "monthly_budget_inr" {
  description = "NF-015: this environment's monthly infrastructure budget in rupees, shown on the cost dashboard (pilot 25,000; 50 stores 1,00,000)."
  type        = number
  default     = 0
}
