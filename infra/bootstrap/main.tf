# ---------------------------------------------------------------------------
# Bootstrap: run once (by a human with Owner on farmerapp-ops). Creates the
# shared ops resources: state bucket, Artifact Registry, GitHub OIDC identity
# and per-environment deployer service accounts. See infra/README.md.
# ---------------------------------------------------------------------------

locals {
  ops_apis = [
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "orgpolicy.googleapis.com",
    "serviceusage.googleapis.com",
    "secretmanager.googleapis.com", # Play upload keystores for mobile-release.yml
  ]

  # Env project ids: either created here or pre-existing.
  env_project_ids = var.create_projects ? { for k, p in google_project.env : k => p.project_id } : var.env_projects

  # All projects that get the SA-key org policy.
  policy_projects = merge({ ops = var.ops_project_id }, local.env_project_ids)

  wif_pool_name = google_iam_workload_identity_pool.gh.name
}

resource "google_project_service" "ops" {
  for_each           = toset(local.ops_apis)
  project            = var.ops_project_id
  service            = each.value
  disable_on_destroy = false
}

# --- Optional: environment projects ---------------------------------------

resource "google_project" "env" {
  for_each = var.create_projects ? var.env_projects : {}

  name            = each.value
  project_id      = each.value
  billing_account = var.billing_account
  folder_id       = var.parent_folder_id != "" ? var.parent_folder_id : null
  org_id          = var.parent_folder_id == "" ? var.org_id : null
  labels          = { app = "farmerapp", env = each.key }

  # No default VPC: envs create their own (modules/network, deny-all ingress). CKV_GCP_27.
  auto_create_network = false
}

# --- Terraform state --------------------------------------------------------

resource "google_storage_bucket" "tfstate" {
  name                        = "${var.ops_project_id}-tfstate"
  project                     = var.ops_project_id
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = var.tfstate_keep_versions
      with_state         = "ARCHIVED"
    }
  }

  labels = { app = "farmerapp", purpose = "tfstate" }

  depends_on = [google_project_service.ops]
}

# --- Artifact Registry --------------------------------------------------------

resource "google_artifact_registry_repository" "apps" {
  project       = var.ops_project_id
  location      = var.region
  repository_id = "apps"
  description   = "FarmerApp container images (api, console, worker, embed). Tag = git SHA."
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "delete-untagged-after-30d"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s"
    }
  }

  cleanup_policies {
    id     = "keep-last-50-tagged"
    action = "KEEP"
    most_recent_versions {
      keep_count = 50
    }
  }

  labels = { app = "farmerapp" }

  depends_on = [google_project_service.ops]
}

# --- GitHub Actions identity (SPEC 9.6, no keys) ----------------------------

resource "google_iam_workload_identity_pool" "gh" {
  project                   = var.ops_project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.ops]
}

resource "google_iam_workload_identity_pool_provider" "gh" {
  project                            = var.ops_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.gh.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.repository == \"${var.github_repository}\""
  oidc { issuer_uri = "https://token.actions.githubusercontent.com" }
}

# --- CI build identity (pushes images) ---------------------------------------

resource "google_service_account" "build" {
  project      = var.ops_project_id
  account_id   = "farmerapp-ci-build"
  display_name = "CI image builder (GitHub Actions)"
}

resource "google_artifact_registry_repository_iam_member" "build_writer" {
  project    = var.ops_project_id
  location   = google_artifact_registry_repository.apps.location
  repository = google_artifact_registry_repository.apps.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.build.email}"
}

resource "google_service_account_iam_member" "build_wif" {
  service_account_id = google_service_account.build.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repository/${var.github_repository}"
}

# --- Deployer service accounts, one per environment -------------------------

resource "google_service_account" "deployer" {
  for_each = local.env_project_ids

  project      = var.ops_project_id
  account_id   = "farmerapp-deployer-${each.key}"
  display_name = "Deployer for ${each.key} (GitHub Actions)"
}

# dev: any ref of the repository may impersonate (PR plans, merge-to-main deploys).
# stg/prd: only refs/heads/main. The production approval gate is the GitHub
# `environment: production` with required reviewers in deploy.yml.
resource "google_service_account_iam_member" "deployer_wif" {
  for_each = local.env_project_ids

  service_account_id = google_service_account.deployer[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member = contains(var.protected_envs, each.key) ? (
    "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.ref/refs/heads/main"
    ) : (
    "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repository/${var.github_repository}"
  )
}

locals {
  deployer_role_bindings = {
    for pair in setproduct(keys(local.env_project_ids), var.deployer_project_roles) :
    "${pair[0]}:${pair[1]}" => { env = pair[0], role = pair[1] }
  }
}

resource "google_project_iam_member" "deployer_env" {
  for_each = local.deployer_role_bindings

  project = local.env_project_ids[each.value.env]
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.deployer[each.value.env].email}"
}

# Deployers pull images from the ops registry and read/write their env's state prefix.
resource "google_artifact_registry_repository_iam_member" "deployer_reader" {
  for_each = local.env_project_ids

  project    = var.ops_project_id
  location   = google_artifact_registry_repository.apps.location
  repository = google_artifact_registry_repository.apps.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.deployer[each.key].email}"
}

resource "google_storage_bucket_iam_member" "deployer_state" {
  for_each = local.env_project_ids

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.deployer[each.key].email}"

  condition {
    title       = "env-prefix-${each.key}"
    description = "Only objects under envs/${each.key}/"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.tfstate.name}/objects/envs/${each.key}/\")"
  }
}

# Cloud Run service agents of each env project must be able to pull images.
resource "google_artifact_registry_repository_iam_member" "run_agent_reader" {
  for_each = local.env_project_ids

  project    = var.ops_project_id
  location   = google_artifact_registry_repository.apps.location
  repository = google_artifact_registry_repository.apps.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${data.google_project.env[each.key].number}@serverless-robot-prod.iam.gserviceaccount.com"
}

data "google_project" "env" {
  for_each   = local.env_project_ids
  project_id = each.value
}

# --- SEC-010: no user-managed service account keys ----------------------------

resource "google_org_policy_policy" "no_sa_keys" {
  for_each = local.policy_projects

  name   = "projects/${each.value}/policies/iam.disableServiceAccountKeyCreation"
  parent = "projects/${each.value}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  depends_on = [google_project_service.ops]
}
