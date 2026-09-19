# Database connection budget (docs/deploy/configuration.md "Connection budget"). Every process
# that opens a SQLAlchemy pool can hold pool_size + max_overflow connections per copy, so
#
#   sum over processes of instances x (pool_size + max_overflow) + reserve
#     <= floor(max_connections x headroom_percent / 100)
#
# must hold, or a scale-out exhausts Cloud SQL before the OPS-003 alert (80%) can fire.
# The plan fails (precondition on the `env` output) when it does not. No providers: the
# check runs in `terraform test` without credentials.

locals {
  per_process = {
    for name, p in var.processes : name => p.instances * (p.pool_size + p.max_overflow)
  }
  app_connections = sum(concat([0], values(local.per_process)))
  ceiling         = floor(var.max_connections * var.headroom_percent / 100)
  total           = local.app_connections + var.reserve
}
