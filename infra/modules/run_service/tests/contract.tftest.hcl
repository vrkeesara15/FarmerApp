# Settings contract preconditions (contract.tf): `terraform test` with a mock provider, no GCP
# credentials. Run by infra/scripts/check.sh.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id            = "p"
  name                  = "api"
  image                 = "img"
  service_account_email = "farmerapp-api@p.iam.gserviceaccount.com"
  vpc_name              = "vpc"
  subnet_name           = "subnet"
  env                   = { APP_ENV = "prd", SERVICE_NAME = "api" }
  secret_env            = { JWT_SIGNING_KEY = "jwt-signing-key" }
  forbidden_env         = ["OTP_DEV_CODE", "PII_LOCAL_KEK"]
}

run "complete_env_plans" {
  command = plan

  variables {
    required_env = ["APP_ENV", "SERVICE_NAME", "JWT_SIGNING_KEY"]
  }
}

run "missing_setting_fails_plan" {
  command = plan

  variables {
    required_env = ["APP_ENV", "SERVICE_NAME", "JWT_SIGNING_KEY", "OTP_PEPPER"]
  }
  expect_failures = [google_cloud_run_v2_service.svc]
}

run "dev_only_setting_fails_plan" {
  command = plan

  variables {
    env = { APP_ENV = "stg", OTP_DEV_CODE = "123456" }
  }
  expect_failures = [google_cloud_run_v2_service.svc]
}

run "plain_and_secret_duplicate_fails_plan" {
  command = plan

  variables {
    env = { APP_ENV = "prd", JWT_SIGNING_KEY = "plain" }
  }
  expect_failures = [google_cloud_run_v2_service.svc]
}
