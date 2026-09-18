output "bucket_names" {
  description = "Short name → bucket name."
  value       = { for k, b in google_storage_bucket.b : k => b.name }
}

output "bucket_urls" {
  description = "Short name → gs:// URL."
  value       = { for k, b in google_storage_bucket.b : k => b.url }
}
