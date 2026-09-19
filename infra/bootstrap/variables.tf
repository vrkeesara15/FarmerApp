variable "ops_project_id" {
  description = "Shared ops project: Terraform state, Artifact Registry and CI identity."
  type        = string
  default     = "farmerapp-ops"
}

variable "region" {
  description = "Default region for ops resources (data residency: India)."
  type        = string
  default     = "asia-south1"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to exchange OIDC tokens, e.g. \"fcc/farmerapp\". Used in the WIF attribute_condition."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in the form owner/name."
  }
}

variable "env_projects" {
  description = "Environment name → GCP project id. Deployer service accounts and the key-creation org policy are created per entry."
  type        = map(string)
  default = {
    dev = "farmerapp-dev"
    stg = "farmerapp-stg"
    prd = "farmerapp-prd"
  }
}

variable "protected_envs" {
  description = "Environments whose deployer may only be impersonated from the main branch (the GitHub environment approval gate is enforced by the workflow's `environment:` setting)."
  type        = set(string)
  default     = ["stg", "prd"]
}

variable "create_projects" {
  description = "Create the environment projects from bootstrap (requires billing_account and parent). If false the projects must already exist."
  type        = bool
  default     = false
}

variable "billing_account" {
  description = "Billing account id used when create_projects = true."
  type        = string
  default     = ""
}

variable "parent_folder_id" {
  description = "Folder id (numeric) the environment projects are created under when create_projects = true. Empty = org root (set org_id)."
  type        = string
  default     = ""
}

variable "org_id" {
  description = "Organisation id, used when create_projects = true and parent_folder_id is empty."
  type        = string
  default     = ""
}

variable "deployer_project_roles" {
  description = "Roles granted to each environment deployer service account on its environment project. Extend deliberately (SEC-010: least privilege)."
  type        = list(string)
  default = [
    "roles/run.admin",              # deploy Cloud Run services, update + execute the migrate job
    "roles/iam.serviceAccountUser", # act as the per-service SAs when deploying
    "roles/viewer",                 # terraform plan / drift detection
    "roles/cloudsql.viewer",
  ]
}

variable "org_policies_enabled" {
  description = "SEC-018: create the project-level org policies (resource locations, no public SQL IP, OS Login, domain-restricted sharing). Needs roles/orgpolicy.policyAdmin for the person applying."
  type        = bool
  default     = true
}

variable "allowed_resource_locations" {
  description = "SEC-018: gcp.resourceLocations allowed values on the env projects (India only)."
  type        = list(string)
  default     = ["in:asia-south1-locations", "in:asia-south2-locations"]
}

variable "allowed_policy_member_customer_ids" {
  description = "SEC-018: Cloud Identity / Workspace customer ids (e.g. C0abc123) allowed in IAM policies (iam.allowedPolicyMemberDomains). Empty = constraint not set."
  type        = list(string)
  default     = []
}

variable "scc_notifications_enabled" {
  description = "SEC-019: create the SCC notification config (org-level; needs SCC Standard activated and org_id) routing HIGH/CRITICAL findings to the scc-findings topic in the ops project."
  type        = bool
  default     = false
}

variable "tfstate_keep_versions" {
  description = "Number of non-current object versions to keep in the state bucket."
  type        = number
  default     = 20
}
