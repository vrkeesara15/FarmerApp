# stg — SPEC 9.2 column "stg". terraform apply is HUMAN-ONLY (never from CI).
project_id          = "farmerapp-stg"
env                 = "stg"
region              = "asia-south1"
domain              = "stg.farmerapp.in"
sql_tier            = "db-custom-1-3840"
sql_read_replica    = false
sql_max_connections = 100 # Cloud SQL default for the tier; confirm with SHOW max_connections
min_instances       = { api = 0, console = 0, worker = 0, embed = 0 }
cloud_armor_enabled = true
cloud_armor_mode    = "preview" # SEC-014: log only
datastream_enabled  = true
deletion_protection = true
notification_email  = ""
# Human: set the pilot tenants' ids before the first stg apply (per-tenant jobs stay
# unscheduled while this is empty). Channels (page/ticket/digest) are created by hand.
job_tenant_ids       = []
location_purge_apply = false
