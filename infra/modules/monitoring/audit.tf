# SEC-017: Admin Activity (always on) + Data Access audit logs for Cloud SQL, Secret Manager
# and GCS, exported by a log sink to a dedicated log bucket with 400-day retention. The bucket
# is locked in prd (`lock_audit_bucket = true`): once locked, retention can only grow and the
# bucket cannot be deleted before every entry has aged out. Locking is irreversible, so it is
# never set in dev / stg.

resource "google_project_iam_audit_config" "data_access" {
  for_each = toset(var.audit_services)

  project = var.project_id
  service = each.value

  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_logging_project_bucket_config" "audit" {
  project        = var.project_id
  location       = var.region
  bucket_id      = "farmerapp-audit"
  retention_days = var.audit_log_retention_days
  locked         = var.lock_audit_bucket
  description    = "SEC-017: Admin Activity + Data Access audit logs (Cloud SQL, Secret Manager, GCS), ${var.audit_log_retention_days} days"
}

# Same-project log bucket destination: no writer-identity grant is needed.
resource "google_logging_project_sink" "audit" {
  project                = var.project_id
  name                   = "farmerapp-audit-sink"
  description            = "SEC-017: every Cloud Audit Logs entry of the project -> farmerapp-audit bucket"
  destination            = "logging.googleapis.com/${google_logging_project_bucket_config.audit.id}"
  filter                 = "logName:\"cloudaudit.googleapis.com\""
  unique_writer_identity = true
}
