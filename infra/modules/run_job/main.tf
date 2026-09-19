resource "google_cloud_run_v2_job" "job" {
  project             = var.project_id
  name                = var.name
  location            = var.region
  deletion_protection = var.deletion_protection
  labels              = { app = "farmerapp", job = var.name }

  template {
    template {
      service_account = var.service_account_email
      timeout         = "${var.timeout_seconds}s"
      max_retries     = var.max_retries

      vpc_access {
        network_interfaces {
          network    = var.vpc_name
          subnetwork = var.subnet_name
        }
        egress = var.egress
      }

      containers {
        image   = var.image # set by CI (gcloud run jobs update --image); ignored below
        args    = var.args
        command = length(var.command) > 0 ? var.command : null
        resources {
          limits = { cpu = var.cpu, memory = var.memory }
        }
        dynamic "env" {
          for_each = var.env
          content {
            name  = env.key
            value = env.value
          }
        }
        dynamic "env" {
          for_each = var.secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image, client, client_version]

    precondition {
      condition     = length(local.missing_env) == 0
      error_message = "${var.name}: required app settings missing from env / secret_env: ${join(", ", local.missing_env)} (apps/api/farmerapp/settings.py CLOUD_REQUIRED_ENV, docs/deploy/configuration.md)."
    }
    precondition {
      condition     = length(local.forbidden_set) == 0
      error_message = "${var.name}: dev-only settings must not be deployed: ${join(", ", local.forbidden_set)}."
    }
    precondition {
      condition     = length(local.duplicate_names) == 0
      error_message = "${var.name}: names set both as plain env and from Secret Manager: ${join(", ", local.duplicate_names)}."
    }
  }
}

# Optional Cloud Scheduler trigger (nightly jobs, SPEC 8.1).
resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  count = var.schedule != "" ? 1 : 0

  project  = var.project_id
  location = google_cloud_run_v2_job.job.location
  name     = google_cloud_run_v2_job.job.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.scheduler_service_account_email}"
}

resource "google_cloud_scheduler_job" "trigger" {
  count = var.schedule != "" ? 1 : 0

  project     = var.project_id
  region      = var.region
  name        = "${var.name}-trigger"
  description = "Runs Cloud Run job ${var.name}"
  schedule    = var.schedule
  time_zone   = var.time_zone

  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.job.name}:run"

    oauth_token {
      service_account_email = var.scheduler_service_account_email
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_invoker]
}
