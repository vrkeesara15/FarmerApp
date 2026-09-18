output "tfstate_bucket" {
  description = "GCS bucket holding all Terraform state."
  value       = google_storage_bucket.tfstate.name
}

output "artifact_registry" {
  description = "Docker registry prefix for application images."
  value       = "${google_artifact_registry_repository.apps.location}-docker.pkg.dev/${var.ops_project_id}/${google_artifact_registry_repository.apps.repository_id}"
}

output "wif_provider" {
  description = "Full resource name of the GitHub OIDC provider. Set as the GitHub Actions variable WIF_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.gh.name
}

output "build_sa_email" {
  description = "Set as GitHub Actions variable BUILD_SA."
  value       = google_service_account.build.email
}

output "deployer_sa_emails" {
  description = "Per-env deployer SA emails. Set as GitHub Actions variables DEPLOY_SA_DEV / DEPLOY_SA_STG / DEPLOY_SA_PRD."
  value       = { for k, sa in google_service_account.deployer : k => sa.email }
}
