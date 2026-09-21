# dev — SPEC 9.2 column "dev". Applied by CI on merge to main.
project_id          = "farmerapp-dev"
env                 = "dev"
region              = "asia-south1"
domain              = "dev.farmerapp.in"
sql_tier            = "db-g1-small"
sql_read_replica    = false
sql_max_connections = 100 # max_connections flag (tier default 50 cannot fit 17 jobs + the reserve); budget 67 / 80 -- room for 6 more jobs
min_instances       = { api = 0, console = 0, worker = 0, embed = 0 }
max_instances       = { api = 3, console = 2, worker = 2, embed = 1 }
cloud_armor_enabled = false
datastream_enabled  = true # M7 kickoff: Datastream -> BigQuery in dev (SPEC 14.4; 9.2 had dev off until M7)
# HUMAN GATE: set true only after docs/runbooks/datastream-cdc-setup.md (replication user,
# password secret version, publication, slot) -- the source profile cannot connect before.
datastream_stream_enabled = false
deletion_protection       = false
notification_email        = ""
# Demo tenants of `jobs seed` (uuid5 of the slugs fcc and gfl), so dev schedules every job.
job_tenant_ids       = ["f14ddecd-97a2-54e9-813a-a2239fcd59ca", "69321438-81a5-5160-9067-6e809e4fd7e5"]
location_purge_apply = false

# Connection budget (module.db_budget, docs/deploy/configuration.md): per instance / job task.
db_pool = {
  api    = { pool_size = 2, max_overflow = 1 }
  worker = { pool_size = 2, max_overflow = 0 }
  jobs   = { pool_size = 1, max_overflow = 1 }
}

# M7 VA-004 review agent (docs/prs/M7-rules.md): off in dev by default.
flag_summary_llm = "off"

# NF-015 / OPS-012 (docs/cost-model.md). dev is not in the pilot budget; it gets a small one
# of its own so a runaway here is caught too. billing_export_table and billing_account stay
# empty until a billing admin has run docs/runbooks/cost-and-budget.md (human gate).
monthly_budget_inr   = 5000
billing_export_table = ""
billing_account      = ""
# OPS-013: dev runs load tests and seeds, so the paging thresholds are loose.
armor_denied_per_5m = 2000
otp_sends_per_5m    = 1000
