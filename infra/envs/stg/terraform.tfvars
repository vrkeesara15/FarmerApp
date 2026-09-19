# stg — SPEC 9.2 column "stg". terraform apply is HUMAN-ONLY (never from CI).
project_id          = "farmerapp-stg"
env                 = "stg"
region              = "asia-south1"
domain              = "stg.farmerapp.in"
sql_tier            = "db-custom-1-3840"
sql_read_replica    = false
sql_max_connections = 125 # max_connections flag (tier default 100); budget 79 / 100 -- room for 10 more jobs. HUMAN APPLY + instance restart (docs/deploy/configuration.md)
min_instances       = { api = 0, console = 0, worker = 0, embed = 0 }
max_instances       = { api = 5, console = 3, worker = 5, embed = 2 }
cloud_armor_enabled = true
cloud_armor_mode    = "preview" # SEC-014: log only
datastream_enabled  = true
# HUMAN GATE (with the human-only stg apply): true after docs/runbooks/datastream-cdc-setup.md.
datastream_stream_enabled = false
deletion_protection       = true
notification_email        = ""
# Human: set the pilot tenants' ids before the first stg apply (per-tenant jobs stay
# unscheduled while this is empty). Channels (page/ticket/digest) are created by hand.
job_tenant_ids       = []
location_purge_apply = false

# Connection budget (module.db_budget, docs/deploy/configuration.md): per instance / job task.
db_pool = {
  api    = { pool_size = 2, max_overflow = 1 }
  worker = { pool_size = 2, max_overflow = 0 }
  jobs   = { pool_size = 1, max_overflow = 1 }
}

# M7 VA-004 review agent (docs/prs/M7-rules.md): on.
flag_summary_llm = "claude"
