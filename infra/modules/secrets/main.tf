# Secrets are created EMPTY. Values are added out-of-band by an admin:
#   gcloud secrets versions add <id> --project <project> --data-file=-
# so no secret value ever touches Terraform state (SPEC 9.7).

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
    for_each = var.rotation_days > 0 && var.rotation_topic != "" ? [1] : []
    content {
      rotation_period = "${var.rotation_days * 86400}s"
    }
  }

  dynamic "topics" {
    for_each = var.rotation_days > 0 && var.rotation_topic != "" ? [1] : []
    content {
      name = "projects/${var.project_id}/topics/${var.rotation_topic}"
    }
  }

  labels = { app = "farmerapp", env = var.env }
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
