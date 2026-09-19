# SPEC 9.5 verbatim, extended with plain env vars, port, probes and invoker IAM.

resource "google_cloud_run_v2_service" "svc" {
  project             = var.project_id
  name                = var.name
  location            = var.region
  ingress             = var.ingress
  deletion_protection = var.deletion_protection
  # SEC-015 / SEC-018: LB-fronted services skip the invoker IAM check instead of granting
  # allUsers (blocked by domain-restricted sharing); ingress = internal LB is the gate.
  invoker_iam_disabled = var.invoker_iam_disabled
  labels               = merge({ app = "farmerapp", service = var.name }, var.labels)

  template {
    service_account                  = var.service_account_email
    max_instance_request_concurrency = var.concurrency
    timeout                          = "${var.timeout_seconds}s"
    labels                           = merge({ app = "farmerapp", service = var.name }, var.labels)

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }
    vpc_access {
      network_interfaces {
        network    = var.vpc_name
        subnetwork = var.subnet_name
      }
      egress = var.egress
    }
    containers {
      image = var.image # set by CI; Terraform ignores later image changes
      resources {
        limits            = { cpu = var.cpu, memory = var.memory }
        cpu_idle          = var.cpu_idle
        startup_cpu_boost = true
      }
      ports {
        container_port = var.container_port
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
      startup_probe {
        initial_delay_seconds = 0
        period_seconds        = 5
        failure_threshold     = 12
        timeout_seconds       = 3
        dynamic "http_get" {
          for_each = var.startup_probe_path != "" ? [1] : []
          content {
            path = var.startup_probe_path
            port = var.container_port
          }
        }
        dynamic "tcp_socket" {
          for_each = var.startup_probe_path == "" ? [1] : []
          content {
            port = var.container_port
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [template[0].containers[0].image, client, client_version]

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

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(var.invoker_members)

  project  = var.project_id
  location = google_cloud_run_v2_service.svc.location
  name     = google_cloud_run_v2_service.svc.name
  role     = "roles/run.invoker"
  member   = each.value
}
