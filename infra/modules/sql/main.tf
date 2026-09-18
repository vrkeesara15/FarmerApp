# SPEC 9.4 verbatim, plus database, IAM users and optional read replica.
# Extensions postgis, vector and pg_trgm are created by the first Alembic
# migration, not by Terraform.
#
# SEC-011 controls, verified by FA-003 (apps/api/alembic/versions/0003_rls_roles.py):
#   - private IP only: ipv4_enabled = false, private_network = var.vpc_id
#   - TLS enforced:    ssl_mode = "ENCRYPTED_ONLY"
#   - IAM DB auth:     database_flags cloudsql.iam_authentication = on + google_sql_user
#                      of type CLOUD_IAM_SERVICE_ACCOUNT per deployable SA (no passwords)
#   - no DDL for the app user: Postgres roles are created by migration 0003, which grants
#                      DML-only `farmerapp_app` and owner/DDL `farmerapp_migrate`; the IAM
#                      users below must be made members (see the google_sql_user comment).

resource "google_sql_database_instance" "main" {
  project             = var.project_id
  name                = "farmerapp-${var.env}"
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = var.env != "dev"

  settings {
    tier              = var.sql_tier
    availability_type = var.env == "prd" ? "REGIONAL" : "ZONAL"
    disk_autoresize   = true
    disk_size         = var.disk_size_gb
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.vpc_id
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = var.enable_datastream_access
    }
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.env == "prd"
      transaction_log_retention_days = 7
      location                       = var.backup_location
      backup_retention_settings { retained_backups = var.env == "prd" ? 30 : 7 }
    }
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
    database_flags {
      name  = "cloudsql.logical_decoding" # needed for Datastream CDC
      value = "on"
    }
    insights_config { query_insights_enabled = true }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = "stable"
    }

    user_labels = { app = "farmerapp", env = var.env }
  }
}

resource "google_sql_database" "app" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.main.name
}

# IAM database users (SEC-011). Postgres role name = SA email without ".gserviceaccount.com".
# They are created with no privileges. Migration 0003 (run by the migrate job as the owner)
# creates the NOLOGIN groups; an admin then runs once per environment, as the instance's
# postgres user:
#   GRANT farmerapp_app     TO "farmerapp-api@<project>.iam", "farmerapp-worker@<project>.iam",
#                              "farmerapp-jobs@<project>.iam";
#   GRANT farmerapp_migrate TO "<migrate SA>@<project>.iam";   -- the SA of the migrate job only
# (`make db-roles` is the local equivalent). The app role has DML only and cannot bypass RLS;
# a runtime SA must never be a member of farmerapp_migrate.
resource "google_sql_user" "iam" {
  for_each = toset(var.iam_service_accounts)

  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = trimsuffix(each.value, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_sql_database_instance" "replica" {
  count = var.read_replica ? 1 : 0

  project              = var.project_id
  name                 = "farmerapp-${var.env}-replica"
  database_version     = "POSTGRES_16"
  region               = var.region
  master_instance_name = google_sql_database_instance.main.name
  deletion_protection  = var.env != "dev"

  settings {
    tier              = var.sql_tier
    availability_type = "ZONAL"
    disk_autoresize   = true
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }
    insights_config { query_insights_enabled = true }

    user_labels = { app = "farmerapp", env = var.env, role = "replica" }
  }
}
