# Settings contract (apps/api/farmerapp/settings.py CLOUD_REQUIRED_ENV, docs/deploy/configuration.md):
# every name the app needs is set, nothing dev-only is, and no name is both a plain and a secret
# env var (Cloud Run would reject the revision). Checked by preconditions on the service.

variable "required_env" {
  description = "Env var names this service must receive (plain env or secret_env). Plan fails when one is missing: the app would start with a local default or refuse to start (prd guard rails)."
  type        = list(string)
  default     = []
}

variable "forbidden_env" {
  description = "Env var names this service must never receive (emulators, mockserver, local keys, the dev OTP code in stg / prd)."
  type        = list(string)
  default     = []
}

locals {
  env_names       = setunion(toset(keys(var.env)), toset(keys(var.secret_env)))
  missing_env     = sort(tolist(setsubtract(toset(var.required_env), local.env_names)))
  forbidden_set   = sort(tolist(setintersection(toset(var.forbidden_env), local.env_names)))
  duplicate_names = sort(tolist(setintersection(toset(keys(var.env)), toset(keys(var.secret_env)))))
}
