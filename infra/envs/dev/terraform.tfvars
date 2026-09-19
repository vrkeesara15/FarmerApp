# dev — SPEC 9.2 column "dev". Applied by CI on merge to main.
project_id          = "farmerapp-dev"
env                 = "dev"
region              = "asia-south1"
domain              = "dev.farmerapp.in"
sql_tier            = "db-g1-small"
sql_read_replica    = false
sql_max_connections = 50 # Cloud SQL default for db-g1-small; confirm with SHOW max_connections
min_instances       = { api = 0, console = 0, worker = 0, embed = 0 }
cloud_armor_enabled = false
datastream_enabled  = false
deletion_protection = false
notification_email  = ""
# Demo tenants of `jobs seed` (uuid5 of the slugs fcc and gfl), so dev schedules every job.
job_tenant_ids       = ["f14ddecd-97a2-54e9-813a-a2239fcd59ca", "69321438-81a5-5160-9067-6e809e4fd7e5"]
location_purge_apply = false
