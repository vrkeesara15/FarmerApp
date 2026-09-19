variable "max_connections" {
  description = "max_connections of the Cloud SQL primary (the database flag set by modules/sql)."
  type        = number

  validation {
    condition     = var.max_connections > 0
    error_message = "max_connections must be positive."
  }
}

variable "headroom_percent" {
  description = "Share of max_connections the apps plus the reserve may use (OPS-003 alerts at 80%)."
  type        = number
  default     = 80
}

variable "reserve" {
  description = "Connections kept free for the migrate job, Datastream, Cloud SQL Studio and admins."
  type        = number
  default     = 20
}

variable "processes" {
  description = "Per process that opens a SQLAlchemy pool: how many copies can run at once (Cloud Run max_instances; for jobs, the number of jobs that may overlap) and its pool. The api / worker / jobs processes get DB_POOL_SIZE / DB_MAX_OVERFLOW from the `env` output."
  type = map(object({
    instances    = number
    pool_size    = number
    max_overflow = number
  }))

  validation {
    # A tenant-bound session holds one connection while ensure_tenant_key loads the tenant's
    # data key on a second one (farmerapp/pii/keys.py), so a pool of 1 would wait on itself.
    condition     = alltrue([for p in values(var.processes) : p.pool_size >= 1 && p.max_overflow >= 0 && p.pool_size + p.max_overflow >= 2])
    error_message = "Every process needs pool_size >= 1, max_overflow >= 0 and pool_size + max_overflow >= 2 (a session plus the PII key load)."
  }
}
