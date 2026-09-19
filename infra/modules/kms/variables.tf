variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name (dev | stg | prd)."
  type        = string
}

variable "region" {
  description = "Key ring location (data residency: asia-south1)."
  type        = string
  default     = "asia-south1"
}

variable "encrypter_decrypters" {
  description = "Members granted roles/cloudkms.cryptoKeyEncrypterDecrypter on the PII key (api, worker, jobs service accounts)."
  type        = list(string)
  default     = []
}
