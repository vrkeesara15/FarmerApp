provider "google" {
  project = var.ops_project_id
  region  = var.region
}

provider "google-beta" {
  project = var.ops_project_id
  region  = var.region
}
