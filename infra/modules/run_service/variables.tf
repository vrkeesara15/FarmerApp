variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "name" {
  description = "Cloud Run service name (api | console | worker | embed)."
  type        = string
}

variable "region" {
  description = "Cloud Run region."
  type        = string
  default     = "asia-south1"
}

variable "image" {
  description = "Initial container image. CI deploys new images; Terraform ignores later image changes (SPEC 9.5)."
  type        = string
}

variable "service_account_email" {
  description = "Runtime service account (one per deployable, SEC-010)."
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

variable "ingress" {
  description = "Ingress setting. LB-fronted services use INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER (SEC-015); internal-only services use INGRESS_TRAFFIC_INTERNAL_ONLY."
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  validation {
    condition     = contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], var.ingress)
    error_message = "ingress must be one of INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "egress" {
  description = "VPC egress: PRIVATE_RANGES_ONLY (default, SPEC 9.5) or ALL_TRAFFIC (route everything through Cloud NAT)."
  type        = string
  default     = "PRIVATE_RANGES_ONLY"
}

variable "min_instances" {
  description = "Minimum instances (0 in dev/stg, 1 in prd for api/console)."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum instances (SPEC 8.1: api max 20)."
  type        = number
  default     = 20
}

variable "cpu" {
  description = "CPU limit per instance."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance."
  type        = string
  default     = "512Mi"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "concurrency" {
  description = "Max concurrent requests per instance."
  type        = number
  default     = 80
}

variable "timeout_seconds" {
  description = "Request timeout."
  type        = number
  default     = 60
}

variable "cpu_idle" {
  description = "Throttle CPU when idle (request-based billing). False keeps CPU always on (worker with background work)."
  type        = bool
  default     = true
}

variable "env" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Env var name → Secret Manager secret id; injected via value_source (latest version)."
  type        = map(string)
  default     = {}
}

variable "invoker_members" {
  description = "Members granted roles/run.invoker. Use [\"allUsers\"] for LB-fronted public services (ingress still restricts to the LB)."
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  description = "Protect the service from `terraform destroy` (on in stg/prd)."
  type        = bool
  default     = false
}

variable "startup_probe_path" {
  description = "HTTP path for the startup probe. Empty = TCP probe on the container port."
  type        = string
  default     = ""
}

variable "labels" {
  description = "Extra labels merged into the service's labels (OPS-012 cost attribution: env, tenant_id on a dedicated service)."
  type        = map(string)
  default     = {}
}

# OPS-012: the Cloud Billing export groups spend by resource label, so every service says
# what it is (`component`) and whose it is (`tenancy`). Every service is `shared` today --
# one multi-tenant deployment -- so modules/cost apportions their cost across tenants;
# `dedicated` plus a `tenant_id` label is what a single-tenant service would set, and the
# cost views bill that directly instead.
variable "tenancy" {
  description = "OPS-012: `shared` (every tenant, cost apportioned) or `dedicated` (one tenant, cost billed to the `tenant_id` label)."
  type        = string
  default     = "shared"

  validation {
    condition     = contains(["shared", "dedicated"], var.tenancy)
    error_message = "tenancy must be shared or dedicated."
  }
}

variable "invoker_iam_disabled" {
  description = "Disable the Cloud Run invoker IAM check (LB-fronted api / console with ingress INTERNAL_LOAD_BALANCER). Replaces an allUsers invoker binding, which domain-restricted sharing (SEC-018) rejects."
  type        = bool
  default     = false
}
