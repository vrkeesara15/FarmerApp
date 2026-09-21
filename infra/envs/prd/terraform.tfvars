# prd — SPEC 9.2 column "prd". terraform apply is HUMAN-ONLY (never from CI).
project_id          = "farmerapp-prd"
env                 = "prd"
region              = "asia-south1"
domain              = "farmerapp.in"
sql_tier            = "db-custom-2-7680" # NF-006: HA REGIONAL + PITR (7 d WAL) + 30 backups derive from env = "prd" (SPEC 9.4)
sql_read_replica    = true
sql_backup_location = "asia-south2"                                   # NF-006: backups stored cross-region (DR restore target region)
sql_max_connections = 250                                             # max_connections flag (tier default 200 for 7.5 GB); budget 154 / 200 -- room for 23 more jobs. HUMAN APPLY + primary and replica restart
min_instances       = { api = 1, console = 1, worker = 0, embed = 0 } # NF-006 / SPEC 9.2: 1/1
cloud_armor_enabled = true
cloud_armor_mode    = "enforce" # SEC-014
datastream_enabled  = true
# HUMAN GATE (with the human-only prd apply): true after docs/runbooks/datastream-cdc-setup.md.
datastream_stream_enabled = false
deletion_protection       = true
lock_audit_bucket         = true # SEC-017: irreversible bucket lock, prd only
notification_email        = ""
availability_goal         = 0.995 # NF-006 pilot; 0.999 at SaaS launch
# Human: set the pilot tenants' ids before the first prd apply; create the page / ticket /
# digest channels by hand and list their ids here.
job_tenant_ids       = []
location_purge_apply = true # SPEC 2.6: raw points older than 180 days are aggregated + dropped

# Connection budget (module.db_budget, docs/deploy/configuration.md): per instance / job task.
db_pool = {
  api    = { pool_size = 2, max_overflow = 1 }
  worker = { pool_size = 2, max_overflow = 0 }
  jobs   = { pool_size = 1, max_overflow = 1 }
}

# M7 VA-004 review agent (docs/prs/M7-rules.md): on.
flag_summary_llm = "claude"

# NF-015 (docs/cost-model.md): pilot (5 stores) under Rs 25,000/month. Raise to 100000 at 50
# stores -- the model says the shape holds; see the "50 stores" column and its levers.
# HUMAN GATE (with the human-only prd apply): billing export + budget binding,
# docs/runbooks/cost-and-budget.md; then set billing_export_table and billing_account.
monthly_budget_inr   = 25000
billing_export_table = ""
billing_account      = ""
# OPS-012 per tenant, per day (excluded from the infra budget by NF-015).
llm_daily_inr_per_tenant = 500
sms_daily_inr_per_tenant = 500
# OPS-013: Armor enforces in prd; a spike here is real traffic being blocked.
armor_denied_per_5m = 500
otp_sends_per_5m    = 300
# OPS-013: set the organisation id to let the SCC service agent publish findings; pointing
# SCC at the topic is a separate org-level human gate (see the alert's documentation).
scc_organization_id = ""
