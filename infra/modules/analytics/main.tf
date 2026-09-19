# Analytics layer (SPEC 5, 9.1): Datastream CDC from Cloud SQL into BigQuery and the datasets
# dbt builds on.
#
#   Cloud SQL (private IP) --PSC interface--> Datastream --> farmerapp_raw (merge mode)
#   dbt (farmerapp-dbt SA): farmerapp_raw -> farmerapp_staging -> farmerapp_marts -> farmerapp_views
#   console (as farmerapp-bi-reader): farmerapp_views only; the views dataset is AUTHORISED on
#   farmerapp_marts, so the reader never gets the marts themselves (AN-013).
#
# Only the columns in replicated_columns.json leave Postgres (AN-014). The replication user,
# publication and slot are created by the one-time SQL in docs/runbooks/datastream-cdc-setup.md
# (migrations own the database; Terraform never holds a database password).

locals {
  ds     = var.datastream_enabled ? 1 : 0
  stream = var.datastream_enabled && var.datastream_stream_enabled ? 1 : 0

  # table -> columns allowlist, shared with dbt (dbt/scripts/check_replication.py).
  replicated = { for t, cols in jsondecode(file("${path.module}/replicated_columns.json")) : t => cols if !startswith(t, "_") }

  labels = { app = "farmerapp", env = var.env, component = "analytics" }

  datastream_agent = "service-${data.google_project.this.number}@gcp-sa-datastream.iam.gserviceaccount.com"
}

data "google_project" "this" {
  project_id = var.project_id
}

# --- Datasets ---------------------------------------------------------------------------------

resource "google_bigquery_dataset" "raw" {
  project                    = var.project_id
  dataset_id                 = "farmerapp_raw"
  friendly_name              = "FarmerApp raw (Datastream CDC)"
  description                = "Datastream merge-mode replica of Cloud SQL (allowlisted columns only, AN-014). Written by Datastream, read by dbt."
  location                   = var.region
  delete_contents_on_destroy = var.env == "dev"
  labels                     = local.labels
}

resource "google_bigquery_dataset" "staging" {
  project                    = var.project_id
  dataset_id                 = "farmerapp_staging"
  friendly_name              = "FarmerApp staging (dbt)"
  description                = "dbt staging views: typed, deduplicated, soft deletes removed, PII dropped or masked."
  location                   = var.region
  delete_contents_on_destroy = var.env == "dev"
  labels                     = local.labels
}

resource "google_bigquery_dataset" "marts" {
  project                    = var.project_id
  dataset_id                 = "farmerapp_marts"
  friendly_name              = "FarmerApp marts (dbt)"
  description                = "SPEC 5.2 KPIs and AN-001..009 marts. Not readable by the console: it reads farmerapp_views."
  location                   = var.region
  delete_contents_on_destroy = var.env == "dev"
  labels                     = local.labels
}

resource "google_bigquery_dataset" "views" {
  project                    = var.project_id
  dataset_id                 = "farmerapp_views"
  friendly_name              = "FarmerApp authorised views"
  description                = "AN-013 authorised views: one row per (viewer_user_id, mart row the viewer may see)."
  location                   = var.region
  delete_contents_on_destroy = var.env == "dev"
  labels                     = local.labels
}

# --- Service accounts -------------------------------------------------------------------------

resource "google_service_account" "dbt" {
  project      = var.project_id
  account_id   = "farmerapp-dbt"
  display_name = "FarmerApp ${var.env} dbt"
  description  = "Runs dbt: reads farmerapp_raw, writes farmerapp_staging / marts / views."
}

resource "google_service_account" "reader" {
  project      = var.project_id
  account_id   = "farmerapp-bi-reader"
  display_name = "FarmerApp ${var.env} BI reader"
  description  = "Reads farmerapp_views only (console dashboards, AN-013)."
}

# Running queries is a project-level permission; data access stays per dataset below.
resource "google_project_iam_member" "job_user" {
  for_each = {
    dbt    = google_service_account.dbt.email
    reader = google_service_account.reader.email
  }

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${each.value}"
}

resource "google_bigquery_dataset_iam_member" "dbt_reads_raw" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_writes" {
  for_each = {
    staging = google_bigquery_dataset.staging.dataset_id
    views   = google_bigquery_dataset.views.dataset_id
  }

  project    = var.project_id
  dataset_id = each.value
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "reader_reads_views" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.views.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.reader.email}"
}

# farmerapp_marts is managed ONLY through google_bigquery_dataset_access: dataset IAM
# resources rewrite the dataset's access list and would drop the authorised-dataset entry.
resource "google_bigquery_dataset_access" "dbt_writes_marts" {
  project       = var.project_id
  dataset_id    = google_bigquery_dataset.marts.dataset_id
  role          = "WRITER"
  user_by_email = google_service_account.dbt.email
}

# AN-013: every view in farmerapp_views may read farmerapp_marts, whoever queries it.
resource "google_bigquery_dataset_access" "views_authorised_on_marts" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.marts.dataset_id

  dataset {
    dataset {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.views.dataset_id
    }
    target_types = ["VIEWS"]
  }
}

resource "google_service_account_iam_member" "dbt_wif" {
  for_each = toset(var.dbt_workload_identity_members)

  service_account_id = google_service_account.dbt.name
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value
}

resource "google_service_account_iam_member" "dbt_impersonators" {
  for_each = toset(var.dbt_impersonators)

  service_account_id = google_service_account.dbt.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

resource "google_service_account_iam_member" "reader_impersonators" {
  for_each = toset(var.reader_impersonators)

  service_account_id = google_service_account.reader.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

# --- Datastream -------------------------------------------------------------------------------

# Datastream's service agent: created on demand so the secret and dataset grants can name it.
resource "google_project_service_identity" "datastream" {
  count    = local.ds
  provider = google-beta

  project = var.project_id
  service = "datastream.googleapis.com"
}

# Datastream writes the replica (dataset-level, not project-wide).
resource "google_bigquery_dataset_iam_member" "datastream_writes_raw" {
  count = local.ds

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${local.datastream_agent}"

  depends_on = [google_project_service_identity.datastream]
}

# Private connectivity through a Private Service Connect interface: Datastream gets an
# interface in this subnet of our VPC, from where Cloud SQL's private IP is reachable over the
# Private Service Access peering (VPC peering would not be transitive to Cloud SQL). No public
# IP, no proxy VM.
resource "google_compute_subnetwork" "datastream" {
  count = local.ds

  project                  = var.project_id
  name                     = "farmerapp-${var.env}-datastream"
  region                   = var.region
  network                  = var.vpc_id
  ip_cidr_range            = var.datastream_subnet_cidr
  private_ip_google_access = true
  description              = "Datastream PSC interface (network attachment) subnet."
}

resource "google_compute_network_attachment" "datastream" {
  count = local.ds

  project     = var.project_id
  name        = "farmerapp-${var.env}-datastream"
  region      = var.region
  description = "Datastream private connection to Cloud SQL (PSC interface)."
  # Datastream's producer project is Google-managed and not known before the private
  # connection exists; the attachment only accepts interfaces in its /28 subnet.
  connection_preference = "ACCEPT_AUTOMATIC"
  subnetworks           = [google_compute_subnetwork.datastream[0].self_link]
}

resource "google_datastream_private_connection" "pc" {
  count = local.ds

  project               = var.project_id
  location              = var.region
  private_connection_id = "farmerapp-${var.env}-psc"
  display_name          = "FarmerApp ${var.env} Datastream (PSC interface)"
  labels                = local.labels

  psc_interface_config {
    network_attachment = google_compute_network_attachment.datastream[0].id
  }
}

resource "google_datastream_connection_profile" "bq" {
  count = local.ds

  project               = var.project_id
  location              = var.region
  connection_profile_id = "farmerapp-${var.env}-bigquery"
  display_name          = "BigQuery farmerapp-${var.env}"
  labels                = local.labels

  bigquery_profile {}
}

resource "google_datastream_connection_profile" "source" {
  count = local.stream

  project               = var.project_id
  location              = var.region
  connection_profile_id = "farmerapp-${var.env}-postgres"
  display_name          = "Cloud SQL farmerapp-${var.env}"
  labels                = local.labels

  postgresql_profile {
    hostname                       = var.sql_private_ip
    port                           = 5432
    username                       = var.datastream_db_user
    database                       = var.database_name
    secret_manager_stored_password = var.datastream_password_secret_version

    ssl_config {
      server_verification {
        ca_certificate = var.sql_server_ca_cert
      }
    }
  }

  private_connectivity {
    private_connection = google_datastream_private_connection.pc[0].id
  }

  lifecycle {
    precondition {
      condition     = var.sql_private_ip != "" && var.datastream_password_secret_version != "" && var.sql_server_ca_cert != ""
      error_message = "The stream needs the Cloud SQL private IP, its server CA and the datastream password secret version (docs/runbooks/datastream-cdc-setup.md)."
    }
  }
}

resource "google_datastream_stream" "cdc" {
  count = local.stream

  project       = var.project_id
  location      = var.region
  stream_id     = "farmerapp-${var.env}-cdc"
  display_name  = "Cloud SQL -> BigQuery CDC"
  desired_state = "RUNNING"
  labels        = local.labels

  source_config {
    source_connection_profile = google_datastream_connection_profile.source[0].id

    postgresql_source_config {
      publication                   = var.publication
      replication_slot              = var.replication_slot
      max_concurrent_backfill_tasks = var.max_concurrent_backfill_tasks

      # AN-014: an explicit table AND column allowlist. A table or column not listed here is
      # never read, even if the publication covers it.
      include_objects {
        postgresql_schemas {
          schema = "public"

          dynamic "postgresql_tables" {
            for_each = local.replicated
            content {
              table = postgresql_tables.key

              dynamic "postgresql_columns" {
                for_each = postgresql_tables.value
                content {
                  column = postgresql_columns.value
                }
              }
            }
          }
        }
      }
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bq[0].id

    bigquery_destination_config {
      data_freshness = var.data_freshness

      single_target_dataset {
        dataset_id = google_bigquery_dataset.raw.id
      }

      # Merge mode: one row per primary key, deletes applied -- an erased farmer disappears
      # from BigQuery with the CDC lag (docs/runbooks/data-subject-erasure.md).
      merge {}
    }
  }

  backfill_all {}

  depends_on = [google_bigquery_dataset_iam_member.datastream_writes_raw]
}
