variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}

variable "topics" {
  description = "Topic names (SPEC 9.2). Each gets a <topic>.dlq dead-letter topic and, when push_endpoint_base is set, a push subscription to the worker."
  type        = list(string)
}

variable "retention" {
  description = "Message retention on topics and subscriptions (7 days)."
  type        = string
  default     = "604800s"
}

variable "push_endpoint_base" {
  description = "Base URL of the worker (e.g. https://worker-xyz-el.a.run.app). Push endpoint = <base>/push (one route; the worker dispatches on the topic attribute). Empty = pull subscriptions only."
  type        = string
  default     = ""
}

variable "push_service_account" {
  description = "Service account email used for the push OIDC token (needs run.invoker on the worker)."
  type        = string
  default     = ""
}

variable "pubsub_service_agent" {
  description = "Pub/Sub service agent email (service-<n>@gcp-sa-pubsub.iam.gserviceaccount.com) that forwards to DLQs."
  type        = string
}

variable "publishers" {
  description = "Members allowed to publish on every topic (api, worker, jobs SAs)."
  type        = list(string)
  default     = []
}

variable "subscription_overrides" {
  description = "Per-topic ack deadline / max delivery attempts of the worker subscription (unset = the module defaults)."
  type = map(object({
    ack_deadline_seconds  = optional(number)
    max_delivery_attempts = optional(number)
  }))
  default = {}
}

variable "max_delivery_attempts" {
  description = "Deliveries before a message is dead-lettered."
  type        = number
  default     = 5
}

variable "ack_deadline_seconds" {
  description = "Ack deadline for push subscriptions (worker handler budget)."
  type        = number
  default     = 60
}
