resource "google_service_account" "sa" {
  for_each = var.service_accounts

  project      = var.project_id
  account_id   = "farmerapp-${each.key}"
  display_name = "FarmerApp ${var.env} ${each.value.display_name}"
}

locals {
  bindings = {
    for pair in flatten([
      for name, sa in var.service_accounts : [
        for role in distinct(concat(var.common_roles, sa.project_roles)) : { name = name, role = role }
      ]
    ]) : "${pair.name}:${pair.role}" => pair
  }
}

resource "google_project_iam_member" "sa_roles" {
  for_each = local.bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.sa[each.value.name].email}"
}

# Pub/Sub service agent needs to mint OIDC tokens for push subscriptions.
resource "google_project_service_identity" "pubsub" {
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"
}

resource "google_project_iam_member" "pubsub_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_project_service_identity.pubsub.email}"
}
