variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "location" {
  description = "Bucket location (India regions only, SEC-018)."
  type        = string
  default     = "ASIA-SOUTH1"
}

variable "buckets" {
  description = "Short name → bucket config. Bucket name becomes farmerapp-<env>-<short name>."
  type = map(object({
    versioning    = optional(bool, false)
    force_destroy = optional(bool, false)
    cors_origins  = optional(list(string), [])
    lifecycle_rules = optional(list(object({
      action_type        = string # Delete | SetStorageClass | AbortIncompleteMultipartUpload
      storage_class      = optional(string)
      age_days           = optional(number)
      num_newer_versions = optional(number)
      with_state         = optional(string)
    })), [])
    # member → role, e.g. "serviceAccount:x@..." → "roles/storage.objectUser"
    iam = optional(map(string), {})
  }))
}

variable "kms_key_name" {
  description = "Optional CMEK key (projects/../cryptoKeys/..). Null = Google-managed keys."
  type        = string
  default     = null
}
