# dev — SPEC 9.2 column "dev". Applied by CI on merge to main.
project_id          = "farmerapp-dev"
env                 = "dev"
region              = "asia-south1"
domain              = "dev.farmerapp.in"
sql_tier            = "db-g1-small"
sql_read_replica    = false
min_instances       = { api = 0, console = 0, worker = 0, embed = 0 }
cloud_armor_enabled = false
datastream_enabled  = false
deletion_protection = false
notification_email  = ""
