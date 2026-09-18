# Environment wiring. The three envs share this file byte-for-byte; every
# difference in SPEC 9.2 is a variable set in terraform.tfvars.
#
# dev  : applied by CI on merge to main (once WIF is configured).
# stg  : terraform apply is human-only, after approval.
# prd  : terraform apply is human-only, after approval. Never from CI.

locals {
  apis = [
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "datastream.googleapis.com",
    "storage.googleapis.com",
  ]

  topics = [
    "visit.created",
    "farmer.registered",
    "diagnosis.requested",
    "payment.webhook",
    "order.created",
    "location.batch",
    "notify.send",
  ]

  # SEC-013: secret id → members that may read it. Values are added by an admin.
  secrets = {
    otp-provider            = ["serviceAccount:${module.iam.emails.api}", "serviceAccount:${module.iam.emails.worker}"]
    razorpay-key-id         = ["serviceAccount:${module.iam.emails.api}", "serviceAccount:${module.iam.emails.worker}"]
    razorpay-key-secret     = ["serviceAccount:${module.iam.emails.api}", "serviceAccount:${module.iam.emails.worker}"]
    razorpay-webhook-secret = ["serviceAccount:${module.iam.emails.api}", "serviceAccount:${module.iam.emails.worker}"]
    llm-api-key             = ["serviceAccount:${module.iam.emails.worker}"]
    jwt-signing-key         = ["serviceAccount:${module.iam.emails.api}"]
  }

  db_env = {
    DB_HOST     = module.sql.private_ip
    DB_NAME     = module.sql.database_name
    DB_IAM_AUTH = "true"
    ENV         = var.env
    GCP_PROJECT = var.project_id
    GCP_REGION  = var.region
  }

  # Nightly jobs (SPEC 8.1) at 02:00 IST, staggered by 30 min to keep the
  # shared dev database responsive. All run from the api image.
  nightly_jobs = {
    nightly-validation = { schedule = "0 2 * * *", args = ["python", "-m", "farmerapp.jobs.validation_batch"] }
    nightly-evaluation = { schedule = "30 2 * * *", args = ["python", "-m", "farmerapp.jobs.evaluation"] }
    exports            = { schedule = "0 3 * * *", args = ["python", "-m", "farmerapp.jobs.exports"] }
    retention-purge    = { schedule = "30 3 * * *", args = ["python", "-m", "farmerapp.jobs.retention_purge"] }
    beat-plan          = { schedule = "0 4 * * *", args = ["python", "-m", "farmerapp.jobs.beat_plan"] }
  }
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "this" {
  project_id = var.project_id
}

# --- Network ---------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  env        = var.env
  region     = var.region
  flow_logs  = var.env == "prd"

  depends_on = [google_project_service.apis]
}

# --- Identity --------------------------------------------------------------

module "iam" {
  source = "../../modules/iam"

  project_id = var.project_id
  env        = var.env

  depends_on = [google_project_service.apis]
}

# --- Cloud SQL -------------------------------------------------------------

module "sql" {
  source = "../../modules/sql"

  project_id               = var.project_id
  env                      = var.env
  region                   = var.region
  sql_tier                 = var.sql_tier
  vpc_id                   = module.network.vpc_id
  read_replica             = var.sql_read_replica
  backup_location          = var.sql_backup_location
  enable_datastream_access = var.datastream_enabled
  iam_service_accounts = [
    module.iam.emails.api,
    module.iam.emails.worker,
    module.iam.emails.jobs,
  ]

  depends_on = [module.network]
}

# --- Secrets (created empty) -------------------------------------------------

module "secrets" {
  source = "../../modules/secrets"

  project_id = var.project_id
  env        = var.env
  region     = var.region
  secrets    = local.secrets

  depends_on = [google_project_service.apis]
}

# --- Buckets (SPEC 9.2) ------------------------------------------------------

module "storage" {
  source = "../../modules/storage"

  project_id = var.project_id
  env        = var.env
  location   = upper(var.region)

  buckets = {
    photos = {
      force_destroy = var.env == "dev"
      cors_origins  = var.cors_origins
      lifecycle_rules = [
        { action_type = "SetStorageClass", storage_class = "NEARLINE", age_days = 90 },
        { action_type = "SetStorageClass", storage_class = "ARCHIVE", age_days = 1095 },
        { action_type = "AbortIncompleteMultipartUpload", age_days = 1 },
      ]
      iam = {
        "serviceAccount:${module.iam.emails.api}"    = "roles/storage.objectUser"
        "serviceAccount:${module.iam.emails.worker}" = "roles/storage.objectViewer"
      }
    }
    exports = {
      force_destroy = var.env == "dev"
      lifecycle_rules = [
        { action_type = "Delete", age_days = 30 },
      ]
      iam = {
        "serviceAccount:${module.iam.emails.api}"  = "roles/storage.objectViewer"
        "serviceAccount:${module.iam.emails.jobs}" = "roles/storage.objectUser"
      }
    }
    corpus = {
      versioning    = true
      force_destroy = var.env == "dev"
      lifecycle_rules = [
        { action_type = "Delete", num_newer_versions = 5, with_state = "ARCHIVED" },
      ]
      iam = {
        "serviceAccount:${module.iam.emails.worker}" = "roles/storage.objectViewer"
        "serviceAccount:${module.iam.emails.jobs}"   = "roles/storage.objectUser"
        "serviceAccount:${module.iam.emails.embed}"  = "roles/storage.objectViewer"
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# --- Cloud Run services ----------------------------------------------------------

module "api" {
  source = "../../modules/run_service"

  project_id            = var.project_id
  name                  = "api"
  region                = var.region
  image                 = var.bootstrap_image
  service_account_email = module.iam.emails.api
  vpc_name              = module.network.vpc_name
  subnet_name           = module.network.subnet_name
  ingress               = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  min_instances         = var.min_instances.api
  max_instances         = var.max_instances.api
  cpu                   = "1"
  memory                = "1Gi"
  deletion_protection   = var.deletion_protection
  invoker_members       = ["allUsers"] # LB-fronted; ingress restricts to the LB
  env = merge(local.db_env, {
    PHOTOS_BUCKET  = module.storage.bucket_names.photos
    EXPORTS_BUCKET = module.storage.bucket_names.exports
    PUBLIC_URL     = "https://api.${var.domain}"
  })
  secret_env = {
    JWT_SIGNING_KEY         = module.secrets.secret_ids.jwt-signing-key
    OTP_PROVIDER            = module.secrets.secret_ids.otp-provider
    RAZORPAY_KEY_ID         = module.secrets.secret_ids.razorpay-key-id
    RAZORPAY_KEY_SECRET     = module.secrets.secret_ids.razorpay-key-secret
    RAZORPAY_WEBHOOK_SECRET = module.secrets.secret_ids.razorpay-webhook-secret
  }

  depends_on = [module.secrets]
}

module "console" {
  source = "../../modules/run_service"

  project_id            = var.project_id
  name                  = "console"
  region                = var.region
  image                 = var.bootstrap_image
  service_account_email = module.iam.emails.console
  vpc_name              = module.network.vpc_name
  subnet_name           = module.network.subnet_name
  ingress               = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  min_instances         = var.min_instances.console
  max_instances         = var.max_instances.console
  container_port        = 3000
  deletion_protection   = var.deletion_protection
  invoker_members       = ["allUsers"]
  env = {
    ENV                 = var.env
    NEXT_PUBLIC_API_URL = "https://api.${var.domain}"
  }
}

module "worker" {
  source = "../../modules/run_service"

  project_id            = var.project_id
  name                  = "worker"
  region                = var.region
  image                 = var.bootstrap_image
  service_account_email = module.iam.emails.worker
  vpc_name              = module.network.vpc_name
  subnet_name           = module.network.subnet_name
  ingress               = "INGRESS_TRAFFIC_INTERNAL" # Pub/Sub push only
  min_instances         = var.min_instances.worker
  max_instances         = var.max_instances.worker
  memory                = "1Gi"
  timeout_seconds       = 300
  concurrency           = 20
  deletion_protection   = var.deletion_protection
  invoker_members       = ["serviceAccount:${module.iam.emails.pubsub-push}"]
  env = merge(local.db_env, {
    PHOTOS_BUCKET = module.storage.bucket_names.photos
    CORPUS_BUCKET = module.storage.bucket_names.corpus
    EMBED_URL     = module.embed.uri
  })
  secret_env = {
    OTP_PROVIDER            = module.secrets.secret_ids.otp-provider
    RAZORPAY_KEY_ID         = module.secrets.secret_ids.razorpay-key-id
    RAZORPAY_KEY_SECRET     = module.secrets.secret_ids.razorpay-key-secret
    RAZORPAY_WEBHOOK_SECRET = module.secrets.secret_ids.razorpay-webhook-secret
    LLM_API_KEY             = module.secrets.secret_ids.llm-api-key
  }

  depends_on = [module.secrets]
}

module "embed" {
  source = "../../modules/run_service"

  project_id            = var.project_id
  name                  = "embed"
  region                = var.region
  image                 = var.bootstrap_image
  service_account_email = module.iam.emails.embed
  vpc_name              = module.network.vpc_name
  subnet_name           = module.network.subnet_name
  ingress               = "INGRESS_TRAFFIC_INTERNAL" # called by worker only
  min_instances         = var.min_instances.embed
  max_instances         = var.max_instances.embed
  cpu                   = "2"
  memory                = "4Gi" # CPU inference in pilot; L4 GPU later (SPEC 8.1)
  concurrency           = 4
  timeout_seconds       = 120
  deletion_protection   = var.deletion_protection
  invoker_members       = ["serviceAccount:${module.iam.emails.worker}"]
  env = {
    ENV           = var.env
    CORPUS_BUCKET = module.storage.bucket_names.corpus
  }
}

# --- Cloud Run jobs ----------------------------------------------------------

module "migrate" {
  source = "../../modules/run_job"

  project_id            = var.project_id
  name                  = "migrate"
  region                = var.region
  image                 = var.bootstrap_image
  args                  = ["alembic", "upgrade", "head"]
  service_account_email = module.iam.emails.jobs
  vpc_name              = module.network.vpc_name
  subnet_name           = module.network.subnet_name
  timeout_seconds       = 900
  max_retries           = 0
  deletion_protection   = var.deletion_protection
  env                   = merge(local.db_env, { DB_ROLE = "migrator" }) # SEC-011: DDL role separate from app role
}

module "nightly" {
  source   = "../../modules/run_job"
  for_each = local.nightly_jobs

  project_id                      = var.project_id
  name                            = each.key
  region                          = var.region
  image                           = var.bootstrap_image
  args                            = each.value.args
  service_account_email           = module.iam.emails.jobs
  vpc_name                        = module.network.vpc_name
  subnet_name                     = module.network.subnet_name
  schedule                        = each.value.schedule
  time_zone                       = "Asia/Kolkata"
  scheduler_service_account_email = module.iam.emails.scheduler
  deletion_protection             = var.deletion_protection
  env = merge(local.db_env, {
    EXPORTS_BUCKET = module.storage.bucket_names.exports
    CORPUS_BUCKET  = module.storage.bucket_names.corpus
  })
  secret_env = {
    LLM_API_KEY = module.secrets.secret_ids.llm-api-key
  }

  depends_on = [module.secrets]
}

# --- Pub/Sub ---------------------------------------------------------------------

module "pubsub" {
  source = "../../modules/pubsub"

  project_id           = var.project_id
  env                  = var.env
  topics               = local.topics
  push_endpoint_base   = module.worker.uri
  push_service_account = module.iam.emails.pubsub-push
  pubsub_service_agent = module.iam.pubsub_service_agent
  publishers = [
    "serviceAccount:${module.iam.emails.api}",
    "serviceAccount:${module.iam.emails.worker}",
    "serviceAccount:${module.iam.emails.jobs}",
  ]
}

# --- Load balancer + Cloud Armor ---------------------------------------------------

module "lb" {
  source = "../../modules/lb"

  project_id           = var.project_id
  env                  = var.env
  region               = var.region
  domain               = var.domain
  api_service_name     = module.api.name
  console_service_name = module.console.name
  cloud_armor_enabled  = var.cloud_armor_enabled
  cloud_armor_mode     = var.cloud_armor_mode
}

# --- Analytics (Datastream → BigQuery) -------------------------------------------

module "analytics" {
  source = "../../modules/analytics"

  project_id                         = var.project_id
  env                                = var.env
  region                             = var.region
  enabled                            = var.datastream_enabled
  vpc_id                             = module.network.vpc_id
  datastream_subnet_cidr             = module.network.datastream_subnet_cidr
  sql_private_ip                     = module.sql.private_ip
  database_name                      = module.sql.database_name
  datastream_password_secret_version = var.datastream_password_secret_version

  depends_on = [google_project_service.apis]
}

# --- Monitoring ------------------------------------------------------------------

module "monitoring" {
  source = "../../modules/monitoring"

  project_id                  = var.project_id
  env                         = var.env
  region                      = var.region
  notification_email          = var.notification_email
  extra_notification_channels = var.extra_notification_channels
  sql_instance_id             = "${var.project_id}:${module.sql.instance_name}"
  lock_audit_bucket           = var.lock_audit_bucket
  uptime_checks = {
    api     = { host = "api.${var.domain}", path = "/healthz" }
    console = { host = "console.${var.domain}", path = "/" }
    webhook = { host = "api.${var.domain}", path = "/v1/payments/webhook/health" }
  }

  depends_on = [google_project_service.apis]
}
