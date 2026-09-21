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
    "iap.googleapis.com",      # SEC-015 console IAP toggle (P1)
    "cloudkms.googleapis.com", # SEC-026 PII key-encryption key
  ]

  # OPS-012: every Cloud Run service and job carries these so the Cloud Billing export can be
  # grouped by environment. `component` and `tenancy` are set by the modules themselves.
  cost_labels = { env = var.env }

  # OPS-014: named once, used by modules/secrets (which creates it and points every secret
  # at it) and by modules/monitoring (which alerts on anything published to it).
  secret_rotation_topic = "secret.rotation"

  topics = [
    "visit.created",
    "farmer.registered",
    "diagnosis.requested",
    "payment.webhook",
    "order.created",
    "location.batch",
    "notify.send",
    "flag.created", # M7 VA-004 review agent: flags raised on the API path -> worker summary
  ]

  # ---------------------------------------------------------------------------------------
  # App settings of api / worker / jobs / migrate (apps/api/farmerapp/settings.py). The full
  # table (name, source, per-env value, who needs it) is docs/deploy/configuration.md. Names
  # here must be exactly what Settings reads: each service's module checks its env against
  # local.required_env (preconditions in modules/run_service and modules/run_job), and
  # apps/api/tests/deploy/test_terraform_env.py compares these maps with settings.py
  # (CLOUD_REQUIRED_ENV) so the two cannot drift apart again.
  # ---------------------------------------------------------------------------------------

  # SEC-011: Cloud SQL IAM database users = service account email minus the domain suffix.
  db_users = {
    for svc in ["api", "worker", "jobs", "migrate"] :
    svc => trimsuffix(module.iam.emails[svc], ".gserviceaccount.com")
  }

  # Plain env layers; local.env_layers lists which layers each process gets (merged in order).
  env_parts = {
    # Every process that loads Settings, the migrate job included.
    base = {
      APP_ENV           = var.env
      GCP_PROJECT       = var.project_id
      LOG_JSON          = "true"
      LOG_LEVEL         = var.log_level
      OTEL_EXPORTER     = "gcp" # NF-014 Cloud Trace (roles/cloudtrace.agent on every SA)
      OTEL_SAMPLE_RATIO = tostring(var.otel_sample_ratio)
      # SEC-011: Cloud SQL Python Connector, private IP, IAM login as DB_USER (no password).
      DB_IAM_AUTH                 = "true"
      DB_INSTANCE_CONNECTION_NAME = module.sql.connection_name
      DB_IP_TYPE                  = "private"
      DB_NAME                     = module.sql.database_name
    }
    # api, worker and jobs: blobs, PII cipher, payments.
    runtime = {
      BLOB_STORE     = "gcs" # SEC-016 V4 signed URLs through IAM signBlob
      PHOTOS_BUCKET  = module.storage.bucket_names.photos
      EXPORTS_BUCKET = module.storage.bucket_names.exports
      # SEC-026: per-tenant data keys wrapped by Cloud KMS (the pepper is a secret below).
      PII_KEK_BACKEND  = "kms"
      PII_KMS_KEY_NAME = module.kms.pii_key_name
      # FA-021 / SEC-023: Razorpay (test-mode keys outside prd); verified webhooks are applied
      # by the worker (payment.webhook push subscription).
      PAYMENT_PROVIDER         = "razorpay"
      PAYMENT_WEBHOOK_DELIVERY = "pubsub"
      RAZORPAY_BASE_URL        = var.razorpay_base_url
    }
    # M6 diagnosis engine (the prd guard rail refuses DIAGNOSIS_ENCODER=fake). The api (corpus
    # uploads, WC-007) and the worker (diagnoses) call `embed` with an OIDC token.
    diagnosis = {
      DIAGNOSIS_ENCODER         = "remote"
      DIAGNOSIS_ENCODER_NAME    = var.diagnosis_encoder_name
      DIAGNOSIS_ENCODER_VERSION = var.diagnosis_encoder_version
      DIAGNOSIS_EMBED_URL       = module.embed.uri
      DIAGNOSIS_LLM             = var.diagnosis_llm
      DIAGNOSIS_LLM_MODEL       = var.diagnosis_llm_model
      DIAGNOSIS_DELIVERY        = "pubsub"
    }
    api = {
      SERVICE_NAME = "api"
      DB_USER      = local.db_users.api
      # OTP over the generic HTTP adapter; the gateway URLs are secrets (they may embed the
      # gateway's auth key). OTP_DEV_CODE is never set by Terraform.
      OTP_PROVIDER = "mockserver"
      CORS_ORIGINS = jsonencode(["https://console.${var.domain}"])
      # SEC-016: signs V4 URLs as itself (Token Creator on itself, below).
      GCS_SIGNING_SERVICE_ACCOUNT = module.iam.emails.api
      # Connection budget (module.db_budget, var.db_pool): the plan fails if the pools of
      # every process at max scale do not fit in 80% of max_connections minus the reserve.
      DB_POOL_SIZE    = module.db_budget.env.api.DB_POOL_SIZE
      DB_MAX_OVERFLOW = module.db_budget.env.api.DB_MAX_OVERFLOW
    }
    worker = {
      SERVICE_NAME    = "worker"
      DB_USER         = local.db_users.worker
      DB_POOL_SIZE    = module.db_budget.env.worker.DB_POOL_SIZE
      DB_MAX_OVERFLOW = module.db_budget.env.worker.DB_MAX_OVERFLOW
      # M7 VA-004 review agent on flag.created (off in dev by default; claude in stg / prd).
      FLAG_SUMMARY_LLM = var.flag_summary_llm
    }
    jobs = {
      SERVICE_NAME    = "jobs"
      DB_USER         = local.db_users.jobs
      DB_POOL_SIZE    = module.db_budget.env.jobs.DB_POOL_SIZE
      DB_MAX_OVERFLOW = module.db_budget.env.jobs.DB_MAX_OVERFLOW
      # M7: flags-summarise (VA-004); DX-011 held-out manifest, DX-012 training exports and
      # candidate models live in the corpus bucket.
      FLAG_SUMMARY_LLM = var.flag_summary_llm
      CORPUS_BUCKET    = module.storage.bucket_names.corpus
    }
    migrate = {
      SERVICE_NAME = "migrate"
      DB_USER      = local.db_users.migrate # SEC-011: the only farmerapp_migrate member
    }
  }
  env_layers = {
    api     = ["base", "runtime", "diagnosis", "api"]
    worker  = ["base", "runtime", "diagnosis", "worker"]
    jobs    = ["base", "runtime", "diagnosis", "jobs"]
    migrate = ["base", "migrate"]
  }
  service_env = {
    for svc, layers in local.env_layers : svc => merge([for layer in layers : local.env_parts[layer]]...)
  }

  # Env var name -> Secret Manager secret id, per process (mounted as `latest`). Accessors
  # of every secret are derived from these maps (local.secrets), so a process can read
  # exactly the secrets it mounts.
  secret_env = {
    api = {
      JWT_SIGNING_KEY         = "jwt-signing-key"
      OTP_PEPPER              = "otp-pepper"
      PII_HASH_PEPPER         = "pii-hash-pepper"
      SMS_PROVIDER_URL        = "otp-sms-provider-url"
      WHATSAPP_PROVIDER_URL   = "otp-whatsapp-provider-url"
      RAZORPAY_KEY_ID         = "razorpay-key-id"
      RAZORPAY_KEY_SECRET     = "razorpay-key-secret"
      RAZORPAY_WEBHOOK_SECRET = "razorpay-webhook-secret"
    }
    worker = {
      PII_HASH_PEPPER         = "pii-hash-pepper"
      RAZORPAY_KEY_ID         = "razorpay-key-id"
      RAZORPAY_KEY_SECRET     = "razorpay-key-secret"
      RAZORPAY_WEBHOOK_SECRET = "razorpay-webhook-secret"
      # DX-004 LLM fallback, read by the Anthropic SDK. Worker only: with
      # DIAGNOSIS_DELIVERY=pubsub the api never calls the LLM.
      ANTHROPIC_API_KEY = "anthropic-api-key"
    }
    jobs = {
      PII_HASH_PEPPER = "pii-hash-pepper"
      # VA-004 flags-summarise (FLAG_SUMMARY_LLM=claude), read by the Anthropic SDK.
      ANTHROPIC_API_KEY = "anthropic-api-key"
    }
    migrate = {}
  }
  # Extra secrets of single jobs (local.jobs keys).
  job_secret_env = {
    reconcile-payments = {
      RAZORPAY_KEY_ID     = "razorpay-key-id"
      RAZORPAY_KEY_SECRET = "razorpay-key-secret"
    }
  }

  # Mirror of CLOUD_REQUIRED_ENV / CLOUD_REQUIRED_JOB_ENV in settings.py (the pytest keeps
  # them equal); enforced per module by preconditions at plan time.
  required_env = {
    api = [
      "APP_ENV", "SERVICE_NAME", "LOG_JSON", "GCP_PROJECT", "OTEL_EXPORTER",
      "DB_IAM_AUTH", "DB_INSTANCE_CONNECTION_NAME", "DB_IP_TYPE", "DB_USER", "DB_NAME",
      "BLOB_STORE", "PHOTOS_BUCKET", "EXPORTS_BUCKET",
      "PII_KEK_BACKEND", "PII_KMS_KEY_NAME", "PII_HASH_PEPPER",
      "DIAGNOSIS_ENCODER", "DIAGNOSIS_ENCODER_NAME", "DIAGNOSIS_ENCODER_VERSION",
      "DIAGNOSIS_EMBED_URL", "DIAGNOSIS_LLM", "DIAGNOSIS_LLM_MODEL", "DIAGNOSIS_DELIVERY",
      "PAYMENT_PROVIDER", "PAYMENT_WEBHOOK_DELIVERY", "RAZORPAY_BASE_URL",
      "RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET",
      "JWT_SIGNING_KEY", "OTP_PEPPER", "OTP_PROVIDER", "SMS_PROVIDER_URL", "WHATSAPP_PROVIDER_URL",
      "CORS_ORIGINS", "GCS_SIGNING_SERVICE_ACCOUNT",
    ]
    worker = [
      "APP_ENV", "SERVICE_NAME", "LOG_JSON", "GCP_PROJECT", "OTEL_EXPORTER",
      "DB_IAM_AUTH", "DB_INSTANCE_CONNECTION_NAME", "DB_IP_TYPE", "DB_USER", "DB_NAME",
      "BLOB_STORE", "PHOTOS_BUCKET", "EXPORTS_BUCKET",
      "PII_KEK_BACKEND", "PII_KMS_KEY_NAME", "PII_HASH_PEPPER",
      "DIAGNOSIS_ENCODER", "DIAGNOSIS_ENCODER_NAME", "DIAGNOSIS_ENCODER_VERSION",
      "DIAGNOSIS_EMBED_URL", "DIAGNOSIS_LLM", "DIAGNOSIS_LLM_MODEL", "DIAGNOSIS_DELIVERY",
      "PAYMENT_PROVIDER", "PAYMENT_WEBHOOK_DELIVERY", "RAZORPAY_BASE_URL",
      "RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET",
      "ANTHROPIC_API_KEY",
    ]
    jobs = [
      "APP_ENV", "SERVICE_NAME", "LOG_JSON", "GCP_PROJECT", "OTEL_EXPORTER",
      "DB_IAM_AUTH", "DB_INSTANCE_CONNECTION_NAME", "DB_IP_TYPE", "DB_USER", "DB_NAME",
      "BLOB_STORE", "PHOTOS_BUCKET", "EXPORTS_BUCKET",
      "PII_KEK_BACKEND", "PII_KMS_KEY_NAME", "PII_HASH_PEPPER",
      "DIAGNOSIS_ENCODER", "DIAGNOSIS_ENCODER_NAME", "DIAGNOSIS_ENCODER_VERSION",
      "DIAGNOSIS_EMBED_URL", "DIAGNOSIS_LLM", "DIAGNOSIS_LLM_MODEL", "DIAGNOSIS_DELIVERY",
      "PAYMENT_PROVIDER", "PAYMENT_WEBHOOK_DELIVERY", "RAZORPAY_BASE_URL",
      "ANTHROPIC_API_KEY", "CORPUS_BUCKET",
    ]
    migrate = [
      "APP_ENV", "SERVICE_NAME", "LOG_JSON", "GCP_PROJECT", "OTEL_EXPORTER",
      "DB_IAM_AUTH", "DB_INSTANCE_CONNECTION_NAME", "DB_IP_TYPE", "DB_USER", "DB_NAME",
    ]
  }
  job_required_env = {
    reconcile-payments = ["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET"]
  }
  # CLOUD_FORBIDDEN_ENV (+ OTP_DEV_CODE outside dev): emulators, mockserver, local keys and
  # password URLs are never deployed.
  forbidden_env = concat(
    [
      "PUBSUB_EMULATOR_HOST", "STORAGE_EMULATOR_HOST", "BLOB_LOCAL_DIR", "PII_LOCAL_KEK",
      "DATABASE_URL", "MIGRATION_DATABASE_URL", "MOCK_RAZORPAY_WEBHOOK_SECRET", "MOCK_RAZORPAY_KEY_ID",
    ],
    var.env == "dev" ? [] : ["OTP_DEV_CODE"],
  )

  # SEC-013: secret id -> members that may read it, derived from the mounts above. Values are
  # added by an admin (`gcloud secrets versions add`); every mounted secret needs a version
  # before the first apply of the services that mount it (Cloud Run resolves `latest`).
  secret_readers = {
    api    = module.iam.emails.api
    worker = module.iam.emails.worker
    jobs   = module.iam.emails.jobs
  }
  mounted_secret_ids = distinct(concat(
    flatten([for svc, m in local.secret_env : values(m)]),
    flatten([for job, m in local.job_secret_env : values(m)]),
  ))
  secrets = merge(
    {
      for id in local.mounted_secret_ids : id => distinct(concat(
        [for svc, m in local.secret_env : "serviceAccount:${local.secret_readers[svc]}" if contains(values(m), id)],
        [for job, m in local.job_secret_env : "serviceAccount:${module.iam.emails.jobs}" if contains(values(m), id)],
      ))
    },
    # Reserved for the DLT SMS / WhatsApp gateway adapter's config (docs/runbooks/
    # otp-provider-outage.md); not mounted until that adapter exists (OTP_PROVIDER is
    # mockserver | fake today).
    { otp-provider = ["serviceAccount:${module.iam.emails.api}"] },
    # M7 / AN-010: password of the Postgres `datastream` login (docs/runbooks/
    # datastream-cdc-setup.md). Read only by the Datastream service agent, never by a service.
    { datastream-db-password = var.datastream_enabled ? ["serviceAccount:${module.analytics.datastream_service_agent}"] : [] },
  )

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
    diagnosis-queue-age = {
      schedule    = "5 * * * *", tenants = true, owner = "agronomist-lead"
      args        = concat(["diagnosis-queue-age"], local.tenant_args)
      description = "OPS-009 / DX-006 review queue > 18 h, LLM fallback rate, re-publish stuck diagnoses, hourly"
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
    # M7 rules follow-ups (docs/prs/M7-rules.md).
    flags-summarise = {
      schedule    = "*/10 * * * *", tenants = true, owner = "product-owner"
      args        = concat(["flags-summarise"], local.tenant_args)
      description = "VA-004 review-agent summaries of flags raised on the API path, every 10 min"
    }
    rules-quality-report = {
      schedule    = "0 3 * * 1", tenants = true, owner = "product-owner"
      args        = concat(["rules-quality-report"], local.tenant_args)
      description = "VA-006 weekly rule precision report and auto-disable, Monday 03:00 IST"
    }
    # M7 farmer P1 (docs/prs/M7-farmer-p1-api.md).
    calendar-reminders = {
      schedule    = "0 7 * * *", tenants = true, owner = "agronomist-lead"
      args        = concat(["calendar-reminders"], local.tenant_args)
      description = "FM-007 crop calendar generation and due-task reminders, daily 07:00 IST"
    }
    outbreak-detection = {
      schedule    = "30 6 * * *", tenants = true, owner = "agronomist-lead"
      args        = concat(["outbreak-detection"], local.tenant_args)
      description = "DX-013 / FM-009 outbreak clusters by district and week, alerts, daily 06:30 IST"
    }
    diagnosis-evaluate = {
      schedule    = "0 1 * * *", tenants = true, owner = "agronomist-lead"
      args        = concat(["diagnosis-evaluate"], local.tenant_args)
      description = "DX-011 nightly evaluation on the held-out field set, drop > 5 points alerts, 01:00 IST"
    }
    export-training-set = {
      schedule    = "0 2 * * 0", tenants = true, owner = "agronomist-lead"
      args        = concat(["export-training-set"], local.tenant_args)
      description = "DX-012 approved corpus field images -> training manifest in the corpus bucket, Sunday 02:00 IST"
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
  max_connections          = var.sql_max_connections
  vpc_id                   = module.network.vpc_id
  read_replica             = var.sql_read_replica
  backup_location          = var.sql_backup_location
  enable_datastream_access = var.datastream_enabled
  iam_service_accounts = [
    module.iam.emails.api,
    module.iam.emails.worker,
    module.iam.emails.jobs,
    module.iam.emails.migrate, # SEC-011: granted farmerapp_migrate only
  ]

  depends_on = [module.network]
}

# --- Database connection budget (docs/deploy/configuration.md "Connection budget") ----
# Worst case: every Cloud Run instance of api / worker at max_instances and every scheduled or
# manual job at once (one task each), each with a full pool. The migrate job (NullPool, one
# connection), Datastream and admins come out of the reserve. Console and embed have no pool.

module "db_budget" {
  source = "../../modules/db_budget"

  max_connections  = module.sql.max_connections
  headroom_percent = 80
  reserve          = 20
  processes = {
    api    = merge(var.db_pool.api, { instances = var.max_instances.api })
    worker = merge(var.db_pool.worker, { instances = var.max_instances.worker })
    jobs   = merge(var.db_pool.jobs, { instances = length(local.jobs) })
  }
}

# --- Cloud KMS (SEC-026 PII key-encryption key) ------------------------------

module "kms" {
  source = "../../modules/kms"

  project_id = var.project_id
  env        = var.env
  region     = var.region
  encrypter_decrypters = [
    "serviceAccount:${module.iam.emails.api}",
    "serviceAccount:${module.iam.emails.worker}",
    "serviceAccount:${module.iam.emails.jobs}",
  ]

  depends_on = [google_project_service.apis]
}

# --- Secrets (created empty) -------------------------------------------------

module "secrets" {
  source = "../../modules/secrets"

  project_id = var.project_id
  env        = var.env
  region     = var.region
  secrets    = local.secrets

  # SEC-013 / OPS-014: 90-day rotation reminders to this topic, which the module owns and
  # modules/monitoring alerts on (a message means "a secret is 90 days old").
  rotation_days  = 90
  rotation_topic = local.secret_rotation_topic

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
        # DX-012: the api signs download URLs of approved on-device models (models/ prefix).
        "serviceAccount:${module.iam.emails.api}" = "roles/storage.objectViewer"
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
  labels                = local.cost_labels
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
  env                   = local.service_env.api
  secret_env            = { for name, id in local.secret_env.api : name => module.secrets.secret_ids[id] }
  required_env          = local.required_env.api
  forbidden_env         = local.forbidden_env

  depends_on = [module.secrets, module.kms]
}

module "console" {
  source = "../../modules/run_service"

  project_id            = var.project_id
  name                  = "console"
  region                = var.region
  labels                = local.cost_labels
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
  labels                = local.cost_labels
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
  env                   = local.service_env.worker
  secret_env            = { for name, id in local.secret_env.worker : name => module.secrets.secret_ids[id] }
  required_env          = local.required_env.worker
  forbidden_env         = local.forbidden_env

  depends_on = [module.secrets, module.kms]
}

module "embed" {
  source = "../../modules/run_service"

  project_id            = var.project_id
  name                  = "embed"
  region                = var.region
  labels                = local.cost_labels
  image                 = var.bootstrap_image
  service_account_email = module.iam.emails.embed
  vpc_name              = module.network.vpc_name
  subnet_name           = module.network.subnet_name
  ingress               = "INGRESS_TRAFFIC_INTERNAL_ONLY" # called by the worker and the api only
  min_instances         = var.min_instances.embed
  max_instances         = var.max_instances.embed
  cpu                   = "2"
  memory                = "4Gi" # CPU inference in pilot; L4 GPU later (SPEC 8.1)
  concurrency           = 4
  timeout_seconds       = 120
  deletion_protection   = var.deletion_protection
  # Every process with DIAGNOSIS_EMBED_URL (local.env_parts.diagnosis) calls it with an OIDC
  # token (tests/deploy/test_terraform_env.py keeps the two lists equal).
  invoker_members = [
    "serviceAccount:${module.iam.emails.worker}", # diagnoses (diagnosis.requested)
    "serviceAccount:${module.iam.emails.api}",    # WC-007 corpus uploads are embedded by the api
    "serviceAccount:${module.iam.emails.jobs}",   # corpus seed / corpus image attach jobs
  ]
  env = {
    ENV           = var.env
    CORPUS_BUCKET = module.storage.bucket_names.corpus
    # ml/embed contract (docs/prs/M6-diagnosis-api.md): refuse any other model / version.
    EMBED_MODEL   = var.diagnosis_encoder_name
    EMBED_VERSION = var.diagnosis_encoder_version
  }
}

# --- Cloud Run jobs ----------------------------------------------------------

module "migrate" {
  source = "../../modules/run_job"

  project_id            = var.project_id
  name                  = "migrate"
  region                = var.region
  labels                = local.cost_labels
  image                 = var.bootstrap_image
  args                  = ["alembic", "upgrade", "head"] # api image (alembic/ + alembic.ini)
  service_account_email = module.iam.emails.migrate      # SEC-011: DDL identity, nothing else
  vpc_name              = module.network.vpc_name
  subnet_name           = module.network.subnet_name
  timeout_seconds       = 900
  max_retries           = 0
  deletion_protection   = var.deletion_protection
  env                   = local.service_env.migrate
  secret_env            = { for name, id in local.secret_env.migrate : name => module.secrets.secret_ids[id] }
  required_env          = local.required_env.migrate
  forbidden_env         = local.forbidden_env
}

module "job" {
  source   = "../../modules/run_job"
  for_each = local.jobs

  project_id            = var.project_id
  name                  = each.key
  region                = var.region
  labels                = local.cost_labels
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
  env                             = local.service_env.jobs
  secret_env = {
    for name, id in merge(local.secret_env.jobs, lookup(local.job_secret_env, each.key, {})) :
    name => module.secrets.secret_ids[id]
  }
  required_env  = distinct(concat(local.required_env.jobs, lookup(local.job_required_env, each.key, [])))
  forbidden_env = local.forbidden_env

  depends_on = [module.secrets, module.kms]
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
  # diagnosis.requested -> worker POST /push: the LLM fallback can take minutes (worker
  # timeout 300 s), and the worker gives up on its own after DIAGNOSIS_MAX_ATTEMPTS (5)
  # deliveries (case -> "unknown", agronomist queue), so the DLQ only catches what that
  # could not handle (7 deliveries).
  subscription_overrides = {
    "diagnosis.requested" = { ack_deadline_seconds = 300, max_delivery_attempts = 7 }
  }
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

# --- Analytics (Datastream → BigQuery, SPEC 5 / 9.1; M7) -------------------------------
# Datasets and the dbt / BI-reader service accounts always exist. datastream_enabled adds the
# private connectivity and BigQuery profile; datastream_stream_enabled (human gate, after the
# one-time SQL of docs/runbooks/datastream-cdc-setup.md) adds the source profile and stream.

module "analytics" {
  source = "../../modules/analytics"

  project_id                = var.project_id
  env                       = var.env
  region                    = var.region
  datastream_enabled        = var.datastream_enabled
  datastream_stream_enabled = var.datastream_stream_enabled
  vpc_id                    = module.network.vpc_id
  datastream_subnet_cidr    = module.network.datastream_subnet_cidr
  sql_private_ip            = module.sql.private_ip
  sql_server_ca_cert        = module.sql.server_ca_cert
  database_name             = module.sql.database_name
  datastream_password_secret_version = (
    var.datastream_password_secret_version != ""
    ? var.datastream_password_secret_version
    : "${module.secrets.secret_names["datastream-db-password"]}/versions/latest"
  )

  # ci-dbt.yml / the scheduled dbt job (WIF principal set by the bootstrap owner) and the
  # console, which reads the authorised views as the BI reader (AN-013).
  dbt_workload_identity_members = var.dbt_workload_identity_members
  dbt_impersonators             = var.dbt_impersonators
  reader_impersonators          = ["serviceAccount:${module.iam.emails.console}"]

  depends_on = [google_project_service.apis]
}

# --- Cost (OPS-012, NF-015) -------------------------------------------------------------
# The landing dataset, the cost views and the daily anomaly watch. The Cloud Billing export
# and the budget's billing-account binding are human gates (billing admin, outside every
# project): once a human has run docs/runbooks/cost-and-budget.md, set billing_export_table
# and billing_account in this env's tfvars and the views, the watch and the budget appear.

module "cost" {
  source = "../../modules/cost"

  project_id           = var.project_id
  env                  = var.env
  region               = var.region
  billing_export_table = var.billing_export_table
  billing_account      = var.billing_account
  marts_dataset        = var.billing_export_table != "" ? module.analytics.marts_dataset : ""
  monthly_budget_inr   = var.monthly_budget_inr
  daily_spend_ratio    = 1.3

  # OPS-012 per-tenant thresholds; NF-015 excludes SMS and LLM from the infra budget, so
  # they are watched on their own rate card (docs/cost-model.md).
  llm_daily_inr_per_tenant = var.llm_daily_inr_per_tenant
  sms_daily_inr_per_tenant = var.sms_daily_inr_per_tenant

  runbook_base_url      = var.runbook_base_url
  notification_channels = module.monitoring.notification_channels

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
  sql_max_connections     = module.sql.max_connections

  # OPS-004 / OPS-005
  pubsub_topics = local.topics
  jobs = merge(
    { for k, j in local.jobs : k => { owner = j.owner, description = j.description } },
    { migrate = { owner = "platform-lead", description = "Alembic upgrade head before each deploy" } },
  )

  # OPS-009 diagnosis review queue and LLM fallback rate (log-based, diagnosis-queue-age job)
  diagnosis_alerts_enabled   = var.diagnosis_alerts_enabled
  diagnosis_queue_age_hours  = 18
  diagnosis_llm_rate_percent = 40

  # OPS-011 Datastream lag and dbt run / test failure. The stream id is the last segment of
  # the stream name; there is none until datastream_stream_enabled, and then the alert is
  # created with it.
  datastream_stream_ids = compact([
    module.analytics.stream_name == null ? "" : element(split("/", module.analytics.stream_name), length(split("/", module.analytics.stream_name)) - 1),
  ])
  datastream_lag_minutes = 30

  # OPS-013 security spikes. The SCC notification config itself is an org-level human gate;
  # scc_organization_id only grants publish on the topic Terraform creates here.
  scc_organization_id = var.scc_organization_id
  armor_denied_per_5m = var.armor_denied_per_5m
  otp_sends_per_5m    = var.otp_sends_per_5m

  # OPS-014 certificate expiry and secret age. The secret-age reminder is published by
  # Secret Manager itself (modules/secrets rotation), so both sides name the same topic.
  cert_expiry_days      = 21
  secret_rotation_topic = local.secret_rotation_topic
  secret_max_age_days   = 90

  # NF-015 / OPS-012: the cost dashboard links to the BigQuery views and quotes the budget.
  cost_dataset       = module.cost.dataset_id
  monthly_budget_inr = var.monthly_budget_inr

  # SLOs (12.1) and SEC-017
  availability_goal = var.availability_goal
  lock_audit_bucket = var.lock_audit_bucket

  depends_on = [google_project_service.apis, module.pubsub, module.job, module.api]
}
