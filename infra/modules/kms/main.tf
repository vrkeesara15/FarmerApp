# SEC-026 / NF-011: Cloud KMS key that wraps the per-tenant PII data keys (PII_KEK_BACKEND=kms,
# PII_KMS_KEY_NAME = the key's id). Symmetric, software protection, in the data-residency
# region, rotated every 90 days (old versions stay enabled, so wrapped data keys still unwrap).
# Key rings and keys cannot be deleted in GCP; prevent_destroy keeps Terraform from trying.

resource "google_kms_key_ring" "ring" {
  project  = var.project_id
  name     = "farmerapp-${var.env}"
  location = var.region
}

resource "google_kms_crypto_key" "pii" {
  name            = "pii"
  key_ring        = google_kms_key_ring.ring.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days (SEC-013); a literal so checkov CKV_GCP_43 can read it
  labels          = { app = "farmerapp", env = var.env, use = "pii-kek" }

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Least privilege: encrypt / decrypt on this key only, for the processes that read or write
# PII fields (api, worker, jobs). The migrate job and the console never see PII keys.
resource "google_kms_crypto_key_iam_member" "users" {
  for_each = toset(var.encrypter_decrypters)

  crypto_key_id = google_kms_crypto_key.pii.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = each.value
}
