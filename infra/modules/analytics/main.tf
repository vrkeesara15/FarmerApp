# BigQuery datasets (raw replica, dbt marts, authorised views) and a Datastream
# CDC stream from Cloud SQL. Everything except the dataset skeleton is gated on
# var.enabled so dev can include the module with enabled = false.

locals {
  n = var.enabled ? 1 : 0
}

resource "google_bigquery_dataset" "raw" {
  project                    = var.project_id
  dataset_id                 = "farmerapp_raw"
  friendly_name              = "FarmerApp raw (Datastream CDC)"
  location                   = var.region
  delete_contents_on_destroy = var.env == "dev"
  labels                     = { app = "farmerapp", env = var.env }
}

resource "google_bigquery_dataset" "marts" {
  project                    = var.project_id
  dataset_id                 = "farmerapp_marts"
  friendly_name              = "FarmerApp marts (dbt)"
  location                   = var.region
  delete_contents_on_destroy = var.env == "dev"
  labels                     = { app = "farmerapp", env = var.env }
}

# Authorised views live here; row filters by tenant/role are defined in dbt (AN-013).
resource "google_bigquery_dataset" "views" {
  project                    = var.project_id
  dataset_id                 = "farmerapp_views"
  friendly_name              = "FarmerApp authorised views"
  location                   = var.region
  delete_contents_on_destroy = var.env == "dev"
  labels                     = { app = "farmerapp", env = var.env }
}

resource "google_bigquery_dataset_iam_member" "marts_readers" {
  for_each = toset(var.dataset_readers)

  project    = var.project_id
  dataset_id = google_bigquery_dataset.marts.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}

# --- Datastream ----------------------------------------------------------

resource "google_datastream_private_connection" "pc" {
  count = local.n

  project               = var.project_id
  location              = var.region
  private_connection_id = "farmerapp-${var.env}-psc"
  display_name          = "FarmerApp ${var.env} Datastream"

  vpc_peering_config {
    vpc    = var.vpc_id
    subnet = var.datastream_subnet_cidr
  }
}

resource "google_datastream_connection_profile" "source" {
  count = local.n

  project               = var.project_id
  location              = var.region
  connection_profile_id = "farmerapp-${var.env}-postgres"
  display_name          = "Cloud SQL farmerapp-${var.env}"

  postgresql_profile {
    hostname                       = var.sql_private_ip
    port                           = 5432
    username                       = var.datastream_db_user
    database                       = var.database_name
    secret_manager_stored_password = var.datastream_password_secret_version
  }

  private_connectivity {
    private_connection = google_datastream_private_connection.pc[0].id
  }
}

resource "google_datastream_connection_profile" "bq" {
  count = local.n

  project               = var.project_id
  location              = var.region
  connection_profile_id = "farmerapp-${var.env}-bigquery"
  display_name          = "BigQuery farmerapp-${var.env}"

  bigquery_profile {}
}

resource "google_datastream_stream" "cdc" {
  count = local.n

  project       = var.project_id
  location      = var.region
  stream_id     = "farmerapp-${var.env}-cdc"
  display_name  = "Cloud SQL → BigQuery CDC"
  desired_state = "RUNNING"

  source_config {
    source_connection_profile = google_datastream_connection_profile.source[0].id

    postgresql_source_config {
      publication      = var.publication
      replication_slot = var.replication_slot
      # PII columns (phone, exact location) are excluded via the publication's
      # column lists in the migration, not here (AN-014).
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bq[0].id

    bigquery_destination_config {
      data_freshness = var.data_freshness

      single_target_dataset {
        dataset_id = google_bigquery_dataset.raw.id
      }
    }
  }

  backfill_all {}
}
