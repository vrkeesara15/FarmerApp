output "env" {
  description = "DB_POOL_SIZE / DB_MAX_OVERFLOW per process (strings, as Cloud Run env)."
  value = {
    for name, p in var.processes : name => {
      DB_POOL_SIZE    = tostring(p.pool_size)
      DB_MAX_OVERFLOW = tostring(p.max_overflow)
    }
  }

  precondition {
    condition     = local.total <= local.ceiling
    error_message = "Database connection budget exceeded: ${join(" + ", [for name, n in local.per_process : "${name} ${n}"])} + reserve ${var.reserve} = ${local.total} > ${var.headroom_percent}% of max_connections ${var.max_connections} (${local.ceiling}). Lower DB_POOL_SIZE / DB_MAX_OVERFLOW (var.db_pool) or max_instances, or raise sql_max_connections."
  }
}

output "connections" {
  description = "Worst-case connections per process."
  value       = local.per_process
}

output "total" {
  description = "Worst-case app connections plus the reserve."
  value       = local.total
}

output "ceiling" {
  description = "floor(max_connections x headroom_percent / 100): the most `total` may be."
  value       = local.ceiling
}
