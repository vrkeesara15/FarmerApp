terraform {
  backend "gcs" {
    bucket = "farmerapp-ops-tfstate"
    prefix = "envs/stg"
  }
}
