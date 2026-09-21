# Secrets are created EMPTY. Values are added out-of-band by an admin:
#   gcloud secrets versions add <id> --project <project> --data-file=-
# so no secret value ever touches Terraform state (SPEC 9.7).

# SEC-013 / OPS-014: every secret carries a 90-day rotation period and the topic Secret
# Manager publishes the reminder to. This module owns the topic (and the publish grant the
# Secret Manager service agent needs, without which creating a secret with a rotation is
# rejected outright), because the rotation metadata and the topic have to be created in the
# same dependency chain. modules/monitoring alerts on anything published to it -- by *name*,
# so the two modules never form a resource edge (monitoring already sits downstream of the
# jobs, which sit downstream of these secrets).

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  rotate = var.rotation_days > 0 && var.rotation_topic != ""
}

resource "google_pubsub_topic" "rotation" {
  count = local.rotate ? 1 : 0

  project = var.project_id
  name    = var.rotation_topic
  labels  = { app = "farmerapp", env = var.env }
}

resource "google_pubsub_topic_iam_member" "rotation_publisher" {
  count = local.rotate ? 1 : 0

  project = var.project_id
  topic   = google_pubsub_topic.rotation[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-secretmanager.iam.gserviceaccount.com"
}

resource "google_secret_manager_secret" "s" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = each.key

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  dynamic "rotation" {
    for_each = local.rotate ? [1] : []
    content {
      rotation_period = "${var.rotation_days * 86400}s"
    }
  }

  dynamic "topics" {
    for_each = local.rotate ? [1] : []
    content {
      name = google_pubsub_topic.rotation[0].id
    }
  }

  labels = { app = "farmerapp", env = var.env }

  # Secret Manager validates the topic and the agent's publish permission at create time.
  depends_on = [google_pubsub_topic_iam_member.rotation_publisher]
}

locals {
  accessors = {
    for pair in flatten([
      for id, members in var.secrets : [for m in members : { id = id, member = m }]
    ]) : "${pair.id}:${pair.member}" => pair
  }
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.accessors

  project   = var.project_id
  secret_id = google_secret_manager_secret.s[each.value.id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
