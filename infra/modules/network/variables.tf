variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name (dev | stg | prd)."
  type        = string
}

variable "region" {
  description = "Region for the subnet, router and NAT."
  type        = string
  default     = "asia-south1"
}

variable "subnet_cidr" {
  description = "Primary CIDR of the Cloud Run (Direct VPC egress) subnet. Needs room for max instances × services."
  type        = string
  default     = "10.10.0.0/22"
}

variable "psa_prefix_length" {
  description = "Prefix length of the range reserved for Private Service Access (Cloud SQL)."
  type        = number
  default     = 16
}

variable "datastream_subnet_cidr" {
  description = "/28 for the Datastream PSC-interface subnet (created by modules/analytics); must not overlap the other VPC or PSA ranges."
  type        = string
  default     = "10.20.0.0/28"
}

variable "flow_logs" {
  description = "Enable VPC flow logs on the subnet (sampled)."
  type        = bool
  default     = false
}
