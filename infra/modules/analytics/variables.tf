variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name (dev | stg | prd)."
  type        = string
}

variable "region" {
  description = "Location of the BigQuery datasets, Datastream and the network attachment."
  type        = string
  default     = "asia-south1"
}

# --- Gates -------------------------------------------------------------------------------
# Two switches because the stream needs one-time database work that migrations do not do
# (docs/runbooks/datastream-cdc-setup.md): the replication user, its password in Secret
# Manager, the publication and the replication slot. Order per environment:
#   1. datastream_enabled = true   -> network attachment, private connection, BigQuery
#                                     profile, Datastream agent can read the password secret
#   2. a human runs the runbook (SQL + `gcloud secrets versions add`)
#   3. datastream_stream_enabled = true -> source profile + stream (backfill, then CDC)
variable "datastream_enabled" {
  description = "Create the Datastream private connectivity and BigQuery destination profile (SPEC 9.2: stg/prd on; dev on from M7)."
  type        = bool
  default     = false
}

variable "datastream_stream_enabled" {
  description = "Create the Postgres source profile and the CDC stream. Set only after the runbook's one-time SQL and secret steps are done (human gate)."
  type        = bool
  default     = false

  validation {
    condition     = !var.datastream_stream_enabled || var.datastream_enabled
    error_message = "datastream_stream_enabled needs datastream_enabled."
  }
}

# --- Source database ---------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC id (projects/<p>/global/networks/<n>) the network attachment subnet lives in; Cloud SQL's private IP is reachable from it through Private Service Access."
  type        = string
  default     = ""
}

variable "datastream_subnet_cidr" {
  description = "CIDR of the subnet backing the Datastream network attachment (PSC interface). Must not overlap the VPC's other ranges or the PSA range."
  type        = string
  default     = "10.20.0.0/28"
}

variable "sql_private_ip" {
  description = "Cloud SQL primary private IP."
  type        = string
  default     = ""
}

variable "sql_server_ca_cert" {
  description = "PEM of the Cloud SQL server CA: Datastream verifies the server certificate (the instance enforces TLS, ssl_mode ENCRYPTED_ONLY)."
  type        = string
  default     = ""
}

variable "database_name" {
  description = "Source database."
  type        = string
  default     = "farmerapp"
}

variable "datastream_db_user" {
  description = "Postgres login Datastream connects as. Created by the runbook's one-time SQL (REPLICATION, SELECT on the replicated tables, an RLS read policy), never by Terraform."
  type        = string
  default     = "datastream"
}

variable "datastream_password_secret_version" {
  description = "Secret Manager version resource name (projects/<p>/secrets/<id>/versions/<v>) holding the datastream user's password. Never the value: a human adds the version (runbook)."
  type        = string
  default     = ""

  validation {
    condition     = var.datastream_password_secret_version == "" || can(regex("^projects/[^/]+/secrets/[^/]+/versions/[^/]+$", var.datastream_password_secret_version))
    error_message = "datastream_password_secret_version must be a secret version resource name, not a password."
  }
}

variable "publication" {
  description = "Postgres publication name (created by the runbook's SQL)."
  type        = string
  default     = "farmerapp_datastream"
}

variable "replication_slot" {
  description = "Postgres logical replication slot name (pgoutput, created by the runbook's SQL)."
  type        = string
  default     = "farmerapp_datastream"
}

variable "data_freshness" {
  description = "BigQuery max staleness of the replicated tables. AN-010 wants Postgres -> marts under 15 min, so the replica itself is kept within 10 min (dbt source freshness warns at 15, errors at 30 -- OPS-011)."
  type        = string
  default     = "600s"
}

variable "max_concurrent_backfill_tasks" {
  description = "Parallel table backfills (each holds one Postgres connection; the db_budget reserve covers them)."
  type        = number
  default     = 2
}

# --- Consumers ---------------------------------------------------------------------------
variable "dbt_workload_identity_members" {
  description = "Principals allowed to act as the dbt service account through Workload Identity Federation (the GitHub repository principalSet for ci-dbt.yml / the scheduled dbt job). Empty = nobody."
  type        = list(string)
  default     = []
}

variable "dbt_impersonators" {
  description = "Members allowed to impersonate the dbt service account (Token Creator), e.g. the data owner's group for local `dbt build --target dev` with DBT_IMPERSONATE_SA."
  type        = list(string)
  default     = []
}

variable "reader_impersonators" {
  description = "Members allowed to impersonate the BI reader service account: the console's service account (dashboards read the authorised views as the reader)."
  type        = list(string)
  default     = []
}
