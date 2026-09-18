variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "name" {
  description = "Job name (migrate, nightly-validation, ...)."
  type        = string
}

variable "region" {
  description = "Cloud Run region."
  type        = string
  default     = "asia-south1"
}

variable "image" {
  description = "Initial container image. CI updates it (gcloud run jobs update --image); Terraform ignores later changes."
  type        = string
}

variable "args" {
  description = "Container args (e.g. [\"alembic\", \"upgrade\", \"head\"])."
  type        = list(string)
  default     = []
}

variable "command" {
  description = "Container entrypoint override. Empty = image default."
  type        = list(string)
  default     = []
}

variable "service_account_email" {
  description = "Runtime service account."
  type        = string
}

variable "vpc_name" {
  description = "VPC name for Direct VPC egress."
  type        = string
}

variable "subnet_name" {
  description = "Subnet name for Direct VPC egress."
  type        = string
}

variable "egress" {
  description = "VPC egress mode."
  type        = string
  default     = "PRIVATE_RANGES_ONLY"
}

variable "cpu" {
  description = "CPU limit."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit."
  type        = string
  default     = "1Gi"
}

variable "timeout_seconds" {
  description = "Task timeout."
  type        = number
  default     = 1800
}

variable "max_retries" {
  description = "Task retries on failure."
  type        = number
  default     = 1
}

variable "env" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Env var name → Secret Manager secret id."
  type        = map(string)
  default     = {}
}

variable "schedule" {
  description = "Cloud Scheduler cron (e.g. \"0 2 * * *\"). Empty = no scheduler trigger (manual/CI-run jobs such as migrate)."
  type        = string
  default     = ""
}

variable "time_zone" {
  description = "Scheduler time zone."
  type        = string
  default     = "Asia/Kolkata"
}

variable "scheduler_service_account_email" {
  description = "SA used by Cloud Scheduler to invoke the job (granted run.invoker on the job). Required when schedule is set."
  type        = string
  default     = ""
}

variable "deletion_protection" {
  description = "Protect the job from destroy."
  type        = bool
  default     = false
}
