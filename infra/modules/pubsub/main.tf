locals {
  topics = toset(var.topics)
  publisher_pairs = {
    for pair in setproduct(var.topics, var.publishers) : "${pair[0]}:${pair[1]}" => { topic = pair[0], member = pair[1] }
  }
}

resource "google_pubsub_topic" "t" {
  for_each = local.topics

  project                    = var.project_id
  name                       = each.value
  message_retention_duration = var.retention
  labels                     = { app = "farmerapp", env = var.env }
}

resource "google_pubsub_topic" "dlq" {
  for_each = local.topics

  project                    = var.project_id
  name                       = "${each.value}.dlq"
  message_retention_duration = var.retention
  labels                     = { app = "farmerapp", env = var.env, dlq = "true" }
}

# Main subscription: push to the worker when an endpoint is configured, else pull.
# The worker serves one route for every topic, POST /push (apps/api/farmerapp/worker/app.py),
# and dispatches on the `topic` message attribute the publishers set (falling back to this
# subscription's name, `<topic>.worker`).
resource "google_pubsub_subscription" "main" {
  for_each = local.topics

  project                    = var.project_id
  name                       = "${each.value}.worker"
  topic                      = google_pubsub_topic.t[each.value].id
  ack_deadline_seconds       = coalesce(try(var.subscription_overrides[each.value].ack_deadline_seconds, null), var.ack_deadline_seconds)
  message_retention_duration = var.retention

  expiration_policy {
    ttl = "" # never expire
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq[each.value].id
    max_delivery_attempts = coalesce(try(var.subscription_overrides[each.value].max_delivery_attempts, null), var.max_delivery_attempts)
  }

  dynamic "push_config" {
    for_each = var.push_endpoint_base != "" ? [1] : []
    content {
      push_endpoint = "${var.push_endpoint_base}/push"
      oidc_token {
        service_account_email = var.push_service_account
        audience              = var.push_endpoint_base
      }
    }
  }

  labels = { app = "farmerapp", env = var.env }
}

# Pull subscription on each DLQ so messages can be inspected and replayed (OPS-004).
resource "google_pubsub_subscription" "dlq" {
  for_each = local.topics

  project                    = var.project_id
  name                       = "${each.value}.dlq.replay"
  topic                      = google_pubsub_topic.dlq[each.value].id
  ack_deadline_seconds       = 60
  message_retention_duration = var.retention

  expiration_policy {
    ttl = ""
  }

  labels = { app = "farmerapp", env = var.env, dlq = "true" }
}

# The Pub/Sub service agent forwards dead letters: publisher on DLQ, subscriber on source.
resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  for_each = local.topics

  project = var.project_id
  topic   = google_pubsub_topic.dlq[each.value].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.pubsub_service_agent}"
}

resource "google_pubsub_subscription_iam_member" "dlq_subscriber" {
  for_each = local.topics

  project      = var.project_id
  subscription = google_pubsub_subscription.main[each.value].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.pubsub_service_agent}"
}

resource "google_pubsub_topic_iam_member" "publishers" {
  for_each = local.publisher_pairs

  project = var.project_id
  topic   = google_pubsub_topic.t[each.value.topic].name
  role    = "roles/pubsub.publisher"
  member  = each.value.member
}
