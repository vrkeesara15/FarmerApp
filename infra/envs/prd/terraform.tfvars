# prd — SPEC 9.2 column "prd". terraform apply is HUMAN-ONLY (never from CI).
project_id          = "farmerapp-prd"
env                 = "prd"
region              = "asia-south1"
domain              = "farmerapp.in"
sql_tier            = "db-custom-2-7680" # NF-006: HA REGIONAL + PITR (7 d WAL) + 30 backups derive from env = "prd" (SPEC 9.4)
sql_read_replica    = true
sql_backup_location = "asia-south2"                                   # NF-006: backups stored cross-region (DR restore target region)
sql_max_connections = 200                                             # max_connections flag (= the tier default for 7.5 GB); budget 142 / 160
min_instances       = { api = 1, console = 1, worker = 0, embed = 0 } # NF-006 / SPEC 9.2: 1/1
cloud_armor_enabled = true
cloud_armor_mode    = "enforce" # SEC-014
datastream_enabled  = true
deletion_protection = true
lock_audit_bucket   = true # SEC-017: irreversible bucket lock, prd only
notification_email  = ""
availability_goal   = 0.995 # NF-006 pilot; 0.999 at SaaS launch
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
