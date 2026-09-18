# prd — SPEC 9.2 column "prd". terraform apply is HUMAN-ONLY (never from CI).
project_id          = "farmerapp-prd"
env                 = "prd"
region              = "asia-south1"
domain              = "farmerapp.in"
sql_tier            = "db-custom-2-7680" # HA REGIONAL + PITR + 30-day backups derive from env = "prd" (SPEC 9.4)
sql_read_replica    = true
sql_backup_location = "asia-south2" # cross-region backup copy
min_instances       = { api = 1, console = 1, worker = 0, embed = 0 }
cloud_armor_enabled = true
cloud_armor_mode    = "enforce"
datastream_enabled  = true
deletion_protection = true
lock_audit_bucket   = true
notification_email  = ""
