# SEC-016: buckets private, uniform access; the API issues 15-minute signed URLs.

resource "google_storage_bucket" "b" {
  for_each = var.buckets

  project                     = var.project_id
  name                        = "farmerapp-${var.env}-${each.key}"
  location                    = var.location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = each.value.force_destroy

  versioning {
    enabled = each.value.versioning
  }

  dynamic "lifecycle_rule" {
    for_each = each.value.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action_type
        storage_class = lifecycle_rule.value.storage_class
      }
      condition {
        age                = lifecycle_rule.value.age_days
        num_newer_versions = lifecycle_rule.value.num_newer_versions
        with_state         = lifecycle_rule.value.with_state
      }
    }
  }

  dynamic "cors" {
    for_each = length(each.value.cors_origins) > 0 ? [1] : []
    content {
      origin          = each.value.cors_origins
      method          = ["GET", "PUT", "HEAD"]
      response_header = ["Content-Type", "x-goog-resumable"]
      max_age_seconds = 900
    }
  }

  dynamic "encryption" {
    for_each = var.kms_key_name == null ? [] : [1]
    content {
      default_kms_key_name = var.kms_key_name
    }
  }

  labels = { app = "farmerapp", env = var.env, bucket = each.key }
}

locals {
  iam_pairs = {
    for pair in flatten([
      for name, cfg in var.buckets : [
        for member, role in cfg.iam : { bucket = name, member = member, role = role }
      ]
    ]) : "${pair.bucket}:${pair.role}:${pair.member}" => pair
  }
}

resource "google_storage_bucket_iam_member" "m" {
  for_each = local.iam_pairs

  bucket = google_storage_bucket.b[each.value.bucket].name
  role   = each.value.role
  member = each.value.member
}
