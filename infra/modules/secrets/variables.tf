variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "region" {
  description = "Replication location (data residency)."
  type        = string
  default     = "asia-south1"
}

variable "secrets" {
  description = "Secret id → list of members allowed to access versions. Values are never set here (SPEC 9.7): an admin runs `gcloud secrets versions add`."
  type        = map(list(string))
}

variable "rotation_days" {
  description = "Rotation reminder period (SEC-013: 90 days). Set 0 to disable."
  type        = number
  default     = 90
}

variable "rotation_topic" {
  description = "Pub/Sub topic id that receives rotation notifications (required by the API when a rotation period is set). Empty disables rotation metadata."
  type        = string
  default     = ""
}
