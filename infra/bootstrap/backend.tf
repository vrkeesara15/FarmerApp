# Bootstrap creates the state bucket it later stores its own state in.
#
# First run (bucket does not exist yet):
#   terraform init -backend=false && terraform apply          # state stays local
# Then migrate the local state into the bucket:
#   terraform init -migrate-state                              # picks up this backend
#
# The local terraform.tfstate is gitignored; delete it after a successful migration.
terraform {
  backend "gcs" {
    bucket = "farmerapp-ops-tfstate"
    prefix = "bootstrap"
  }
}
