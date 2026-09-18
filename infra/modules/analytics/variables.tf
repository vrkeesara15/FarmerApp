variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "region" {
  description = "Location for BigQuery datasets and Datastream."
  type        = string
  default     = "asia-south1"
}

variable "enabled" {
  description = "Create Datastream → BigQuery replication (off in dev, on in stg/prd per SPEC 9.2; dev enabled in M7)."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC id for the Datastream private connection."
  type        = string
  default     = ""
}

variable "datastream_subnet_cidr" {
  description = "/29 for the Datastream peering."
  type        = string
  default     = "10.20.0.0/29"
}

variable "sql_private_ip" {
  description = "Cloud SQL primary private IP."
  type        = string
  default     = ""
}

variable "database_name" {
  description = "Source database."
  type        = string
  default     = "farmerapp"
}

variable "datastream_db_user" {
  description = "Postgres user Datastream connects as (created by a migration with REPLICATION and SELECT on replicated tables)."
  type        = string
  default     = "datastream"
}

variable "datastream_password_secret_version" {
  description = "Secret Manager version resource name (projects/../secrets/../versions/..) holding the Datastream DB password. Never the value."
  type        = string
  default     = ""
}

variable "publication" {
  description = "Postgres publication name (created by migration)."
  type        = string
  default     = "farmerapp_datastream"
}

variable "replication_slot" {
  description = "Postgres replication slot name (created by migration)."
  type        = string
  default     = "farmerapp_datastream"
}

variable "data_freshness" {
  description = "Max staleness of BigQuery data (OPS-011 alerts at 30 min lag)."
  type        = string
  default     = "900s"
}

variable "dataset_readers" {
  description = "Members granted read on the marts dataset (console/dbt SAs)."
  type        = list(string)
  default     = []
}
