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
    "iap.googleapis.com", # SEC-015 console IAP toggle (P1)
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
    razorpay-key-id         = ["serviceAccount:${module.iam.emails.api}", "serviceAccount:${module.iam.emails.worker}", "serviceAccount:${module.iam.emails.jobs}"]
    razorpay-key-secret     = ["serviceAccount:${module.iam.emails.api}", "serviceAccount:${module.iam.emails.worker}", "serviceAccount:${module.iam.emails.jobs}"]
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

  # Scheduled Cloud Run Jobs: one per `python -m farmerapp.jobs <command>` of
  # apps/api/farmerapp/jobs/cli.py, run from the jobs image (deploy.yml). Cron in IST
  # (Cloud Scheduler time_zone Asia/Kolkata). Per-tenant commands get `--tenant-id` once per
  # entry of var.job_tenant_ids; while that list is empty they are created but not scheduled.
  # schedule = "" -> manual one-off (`gcloud run jobs execute <name>`).
  # OPS-005: every job below gets its own failure alert (owner from `owner`).
  tenant_args  = flatten([for t in var.job_tenant_ids : ["--tenant-id", t]])
  have_tenants = length(var.job_tenant_ids) > 0

  jobs = {
    run-rules-batch = {
      schedule    = "0 2 * * *", tenants = true, owner = "product-owner"
      args        = concat(["run-rules", "--mode", "batch"], local.tenant_args)
      description = "VA-001 nightly validation rules, batch mode, 02:00 IST"
    }
    flags-sla-escalation = {
      schedule    = "0 * * * *", tenants = true, owner = "product-owner"
      args        = concat(["flags-sla-escalation"], local.tenant_args)
      description = "OPS-010 escalate flags past SLA, hourly"
    }
    officer-sync-silence = {
      schedule    = "*/15 * * * *", tenants = true, owner = "ops-lead"
      args        = concat(["officer-sync-silence"], local.tenant_args)
      description = "OPS-006 officers on duty with no sync for 2 h, every 15 min"
    }
    auto-end-duty = {
      schedule    = "*/10 * * * *", tenants = true, owner = "ops-lead"
      args        = concat(["auto-end-duty"], local.tenant_args)
      description = "VV-007 auto-end duty sessions, every 10 min"
    }
    ensure-partitions = {
      schedule    = "30 0 * * *", tenants = false, owner = "platform-lead"
      args        = ["ensure-partitions"]
      description = "location_point daily partitions ahead, daily 00:30 IST"
    }
    purge-location-points = {
      schedule    = "0 4 * * *", tenants = false, owner = "platform-lead"
      args        = concat(["purge-location-points"], var.location_purge_apply ? ["--apply"] : [])
      description = "SPEC 2.6 raw location retention (dry run unless location_purge_apply), daily 04:00 IST"
    }
    purge-expired = {
      schedule    = "15 * * * *", tenants = true, owner = "platform-lead"
      args        = concat(["purge-expired"], local.tenant_args)
      description = "NF-003 expired upload sessions and idempotency keys, hourly"
    }
    store-day-watch = {
      schedule    = "15 22 * * *", tenants = true, owner = "ops-lead"
      args        = concat(["store-day-watch"], local.tenant_args)
      description = "OPS-007 stores with zero sales / day not closed by 22:00, daily 22:15 IST"
    }
    reconcile-payments = {
      schedule    = "0 6 * * *", tenants = true, owner = "finance-lead"
      args        = concat(["reconcile-payments"], local.tenant_args)
      description = "OPS-008 Razorpay settlements vs payments of yesterday, 06:00 IST"
    }
    backfill-farm-photo-phash = {
      schedule    = "", tenants = true, owner = "platform-lead"
      args        = concat(["backfill-farm-photo-phash"], local.tenant_args)
      description = "VA-F08 one-off perceptual-hash backfill, manual"
    }
  }
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
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
        "serviceAccount:${module.iam.emails.jobs}"   = "roles/storage.objectViewer" # backfill-farm-photo-phash
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
  ingress               = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" # SEC-015
  invoker_iam_disabled  = true                                     # LB-fronted; ingress is the gate
  min_instances         = var.min_instances.api                    # NF-006: 1 in prd
  max_instances         = var.max_instances.api
  cpu                   = "1"
  memory                = "1Gi"
  container_port        = 8000 # apps/api/Dockerfile (uvicorn --port 8000)
  startup_probe_path    = "/v1/health"
  deletion_protection   = var.deletion_protection
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
  ingress               = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" # SEC-015
  invoker_iam_disabled  = true
  min_instances         = var.min_instances.console # NF-006: 1 in prd
  max_instances         = var.max_instances.console
  container_port        = 3000 # apps/console/Dockerfile (Next standalone server)
  deletion_protection   = var.deletion_protection
  env = {
    ENV = var.env
    # Server-side calls (session cookie routes); the browser bundle has NEXT_PUBLIC_API_URL
    # inlined at image build time (deploy.yml build-arg).
    API_URL             = "https://api.${var.domain}"
    NEXT_PUBLIC_API_URL = "https://api.${var.domain}"
  }
}

# SEC-016: the API signs GCS V4 URLs (15 min) with its own identity through IAM signBlob
# (no key file), which needs Service Account Token Creator on itself.
resource "google_service_account_iam_member" "api_self_sign" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.iam.emails.api}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${module.iam.emails.api}"
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
  ingress               = "INGRESS_TRAFFIC_INTERNAL_ONLY" # Pub/Sub push only
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
  ingress               = "INGRESS_TRAFFIC_INTERNAL_ONLY" # called by worker only
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

module "job" {
  source   = "../../modules/run_job"
  for_each = local.jobs

  project_id            = var.project_id
  name                  = each.key
  region                = var.region
  image                 = var.bootstrap_image
  command               = ["python", "-m", "farmerapp.jobs"] # same in the api and jobs images
  args                  = each.value.args
  service_account_email = module.iam.emails.jobs
  vpc_name              = module.network.vpc_name
  subnet_name           = module.network.subnet_name
  # Per-tenant jobs stay unscheduled until var.job_tenant_ids is set.
  schedule                        = each.value.tenants && !local.have_tenants ? "" : each.value.schedule
  time_zone                       = "Asia/Kolkata"
  scheduler_service_account_email = module.iam.emails.scheduler
  deletion_protection             = var.deletion_protection
  env = merge(local.db_env, {
    PHOTOS_BUCKET  = module.storage.bucket_names.photos
    EXPORTS_BUCKET = module.storage.bucket_names.exports
    CORPUS_BUCKET  = module.storage.bucket_names.corpus
  })
  secret_env = each.key == "reconcile-payments" ? {
    RAZORPAY_KEY_ID     = module.secrets.secret_ids.razorpay-key-id
    RAZORPAY_KEY_SECRET = module.secrets.secret_ids.razorpay-key-secret
  } : {}

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
  console_iap_enabled  = var.console_iap_enabled
  console_iap_members  = var.console_iap_members

  depends_on = [google_project_service.apis]
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
  runbook_base_url            = var.runbook_base_url
  notification_email          = var.notification_email
  page_channels               = var.page_channels
  ticket_channels             = var.ticket_channels
  digest_channels             = var.digest_channels
  extra_notification_channels = var.extra_notification_channels

  # OPS-001 (paths exempt from the Cloud Armor geo rule). The webhook only accepts signed
  # POSTs: a GET answering 405 proves the route is served end to end.
  uptime_checks = {
    api     = { host = "api.${var.domain}", path = "/v1/health" }
    console = { host = "console.${var.domain}", path = "/login" }
    webhook = { host = "api.${var.domain}", path = "/v1/webhooks/razorpay", accepted_status = 405 }
  }

  # OPS-003
  sql_instance_id         = "${var.project_id}:${module.sql.instance_name}"
  sql_replica_instance_id = var.sql_read_replica ? "${var.project_id}:${module.sql.replica_instance_name}" : ""
  sql_max_connections     = var.sql_max_connections

  # OPS-004 / OPS-005
  pubsub_topics = local.topics
  jobs = merge(
    { for k, j in local.jobs : k => { owner = j.owner, description = j.description } },
    { migrate = { owner = "platform-lead", description = "Alembic upgrade head before each deploy" } },
  )

  # SLOs (12.1) and SEC-017
  availability_goal = var.availability_goal
  lock_audit_bucket = var.lock_audit_bucket

  depends_on = [google_project_service.apis, module.pubsub, module.job, module.api]
}
