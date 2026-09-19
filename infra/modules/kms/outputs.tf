output "pii_key_name" {
  description = "PII_KMS_KEY_NAME: projects/<p>/locations/<region>/keyRings/<ring>/cryptoKeys/pii."
  value       = google_kms_crypto_key.pii.id
}
