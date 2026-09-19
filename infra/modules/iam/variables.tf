variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "service_accounts" {
  description = "One service account per deployable (SEC-010). Key = short name, value = display name and project-level roles."
  type = map(object({
    display_name  = string
    project_roles = list(string)
  }))
  default = {
    api = {
      display_name  = "api (FastAPI)"
      project_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser", "roles/pubsub.publisher"]
    }
    worker = {
      display_name  = "worker (Pub/Sub handlers)"
      project_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser", "roles/pubsub.publisher"]
    }
    jobs = {
      display_name  = "jobs (batch, migrations)"
      project_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser", "roles/pubsub.publisher"]
    }
    console = {
      display_name  = "console (Next.js)"
      project_roles = []
    }
    embed = {
      display_name  = "embed (vision encoder)"
      project_roles = []
    }
    pubsub-push = {
      display_name  = "Pub/Sub push subscriptions → worker"
      project_roles = []
    }
    scheduler = {
      display_name  = "Cloud Scheduler → Cloud Run Jobs"
      project_roles = []
    }
  }
}

variable "push_service_account_key" {
  description = "Key in service_accounts of the identity Pub/Sub push subscriptions use (OIDC tokens minted by the Pub/Sub service agent)."
  type        = string
  default     = "pubsub-push"
}

variable "common_roles" {
  description = "Roles every service account gets (observability)."
  type        = list(string)
  default     = ["roles/logging.logWriter", "roles/monitoring.metricWriter", "roles/cloudtrace.agent"]
}
