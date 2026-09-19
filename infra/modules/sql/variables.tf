variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name (dev | stg | prd). Drives HA, PITR and deletion protection per SPEC 9.4."
  type        = string
}

variable "region" {
  description = "Cloud SQL region."
  type        = string
  default     = "asia-south1"
}

variable "sql_tier" {
  description = "Machine tier: db-g1-small (dev), db-custom-1-3840 (stg), db-custom-2-7680 (prd)."
  type        = string
  default     = "db-g1-small"
}

variable "max_connections" {
  description = "max_connections database flag of the primary and the replica. modules/db_budget sizes the app pools against it; OPS-003 alerts at 80%."
  type        = number

  validation {
    condition     = var.max_connections >= 25 && var.max_connections <= 5000
    error_message = "max_connections must be between 25 and 5000."
  }
}

variable "vpc_id" {
  description = "VPC id for the private IP (Private Service Access must already exist)."
  type        = string
}

variable "database_name" {
  description = "Application database name."
  type        = string
  default     = "farmerapp"
}

variable "disk_size_gb" {
  description = "Initial disk size (autoresize is on)."
  type        = number
  default     = 10
}

variable "read_replica" {
  description = "Create a read replica (prd)."
  type        = bool
  default     = false
}

variable "backup_location" {
  description = "Region where automated backups are stored. prd uses asia-south2 (cross-region copy, SPEC 9.2)."
  type        = string
  default     = null
}

variable "iam_service_accounts" {
  description = "Service account emails that log in with IAM database authentication (SEC-011). Postgres groups farmerapp_app / farmerapp_migrate come from migration 0003; membership is granted per environment (see main.tf)."
  type        = list(string)
  default     = []
}

variable "maintenance_day" {
  description = "Maintenance window day (1 = Monday ... 7 = Sunday)."
  type        = number
  default     = 2
}

variable "maintenance_hour" {
  description = "Maintenance window hour in UTC (21 UTC = 02:30 IST)."
  type        = number
  default     = 21
}

variable "enable_datastream_access" {
  description = "Allow Google services (Datastream) to reach the private IP via PSA."
  type        = bool
  default     = false
}
