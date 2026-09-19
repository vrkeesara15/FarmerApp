# Settings contract preconditions (contract.tf): `terraform test` with a mock provider, no GCP
# credentials. Run by infra/scripts/check.sh.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id            = "p"
  name                  = "migrate"
  image                 = "img"
  service_account_email = "farmerapp-migrate@p.iam.gserviceaccount.com"
  vpc_name              = "vpc"
  subnet_name           = "subnet"
  env                   = { APP_ENV = "prd", DB_USER = "farmerapp-migrate@p.iam" }
  secret_env            = { PII_HASH_PEPPER = "pii-hash-pepper" }
  forbidden_env         = ["DATABASE_URL", "OTP_DEV_CODE"]
}

run "complete_env_plans" {
  command = plan

  variables {
    required_env = ["APP_ENV", "DB_USER", "PII_HASH_PEPPER"]
  }
}

run "missing_setting_fails_plan" {
  command = plan

  variables {
    required_env = ["APP_ENV", "DB_USER", "DB_INSTANCE_CONNECTION_NAME"]
  }
  expect_failures = [google_cloud_run_v2_job.job]
}

run "dev_only_setting_fails_plan" {
  command = plan

  variables {
    env = { APP_ENV = "prd", DB_USER = "u", DATABASE_URL = "postgresql://u:pw@h/db" }
  }
  expect_failures = [google_cloud_run_v2_job.job]
}

run "plain_and_secret_duplicate_fails_plan" {
  command = plan

  variables {
    env = { APP_ENV = "prd", PII_HASH_PEPPER = "x" }
  }
  expect_failures = [google_cloud_run_v2_job.job]
}
