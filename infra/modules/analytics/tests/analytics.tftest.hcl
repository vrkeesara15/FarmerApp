# Analytics module contract (M7, AN-013 / AN-014): gates, column allowlist, least-privilege
# grants. `terraform test` with mock providers, no GCP credentials. Run by infra/scripts/check.sh.

mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789"
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id = "farmerapp-dev"
  env        = "dev"
  vpc_id     = "projects/farmerapp-dev/global/networks/farmerapp-dev"
}

run "datasets_and_service_accounts_without_datastream" {
  command = plan

  assert {
    condition     = length(google_datastream_private_connection.pc) == 0 && length(google_datastream_stream.cdc) == 0
    error_message = "Datastream resources must not exist while datastream_enabled = false."
  }
  assert {
    condition = toset([
      google_bigquery_dataset.raw.dataset_id, google_bigquery_dataset.staging.dataset_id,
      google_bigquery_dataset.marts.dataset_id, google_bigquery_dataset.views.dataset_id,
    ]) == toset(["farmerapp_raw", "farmerapp_staging", "farmerapp_marts", "farmerapp_views"])
    error_message = "The four datasets dbt writes to (macros/schema.sql) must exist."
  }
}

run "connectivity_without_stream" {
  command = plan

  variables {
    datastream_enabled = true
  }

  assert {
    condition     = length(google_datastream_private_connection.pc) == 1 && length(google_compute_network_attachment.datastream) == 1
    error_message = "datastream_enabled creates the PSC-interface private connection."
  }
  assert {
    condition     = length(google_datastream_connection_profile.source) == 0 && length(google_datastream_stream.cdc) == 0
    error_message = "The source profile and stream wait for datastream_stream_enabled (human gate)."
  }
}

run "stream_replicates_only_the_allowlist" {
  command = plan

  variables {
    datastream_enabled                 = true
    datastream_stream_enabled          = true
    sql_private_ip                     = "10.30.0.3"
    sql_server_ca_cert                 = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
    datastream_password_secret_version = "projects/123456789/secrets/datastream-db-password/versions/latest"
  }

  assert {
    condition     = length(google_datastream_stream.cdc[0].source_config[0].postgresql_source_config[0].include_objects[0].postgresql_schemas[0].postgresql_tables) == length(keys(jsondecode(file("replicated_columns.json")))) - 1
    error_message = "Every allowlisted table (and only those) is replicated."
  }
  assert {
    condition = length(setintersection(
      toset(flatten([
        for t in google_datastream_stream.cdc[0].source_config[0].postgresql_source_config[0].include_objects[0].postgresql_schemas[0].postgresql_tables :
        [for c in t.postgresql_columns : "${t.table}.${c.column}"]
      ])),
      toset(["farmer.name", "farmer.phone", "farmer.phone_enc", "farmer.phone_hash", "farmer.landmark",
        "user.name", "user.phone", "user.home_point", "visit.checkin_point", "visit.notes",
      "refresh_token.token_hash", "flag.evidence", "flag.title"])
    )) == 0
    error_message = "AN-014: a PII column is in the Datastream allowlist."
  }
  assert {
    condition     = length(google_datastream_stream.cdc[0].destination_config[0].bigquery_destination_config[0].merge) == 1
    error_message = "Merge mode: deletes (data-subject erasure) must propagate to BigQuery."
  }
}

run "stream_needs_connectivity" {
  command = plan

  variables {
    datastream_stream_enabled = true
  }
  expect_failures = [var.datastream_stream_enabled]
}

run "stream_needs_secret_and_ca" {
  command = plan

  variables {
    datastream_enabled        = true
    datastream_stream_enabled = true
    sql_private_ip            = "10.30.0.3"
  }
  expect_failures = [google_datastream_connection_profile.source]
}

run "password_value_is_rejected" {
  command = plan

  variables {
    datastream_password_secret_version = "hunter2"
  }
  expect_failures = [var.datastream_password_secret_version]
}

run "reader_reads_only_the_views" {
  command = plan

  variables {
    reader_impersonators = ["serviceAccount:farmerapp-console@farmerapp-dev.iam.gserviceaccount.com"]
  }

  assert {
    condition     = google_bigquery_dataset_iam_member.reader_reads_views.dataset_id == "farmerapp_views" && google_bigquery_dataset_iam_member.reader_reads_views.role == "roles/bigquery.dataViewer"
    error_message = "AN-013: the BI reader gets read on farmerapp_views only."
  }
  assert {
    condition     = google_bigquery_dataset_access.views_authorised_on_marts.dataset[0].dataset[0].dataset_id == "farmerapp_views"
    error_message = "AN-013: farmerapp_views must be authorised on farmerapp_marts."
  }
  assert {
    condition     = length(google_service_account_iam_member.reader_impersonators) == 1
    error_message = "The console impersonates the reader."
  }
}
