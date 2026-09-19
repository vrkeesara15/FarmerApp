# Connection budget precondition (outputs.tf): `terraform test`, no providers or credentials.
# Run by infra/scripts/check.sh and ci-infra.yml.

variables {
  max_connections = 200
  processes = {
    api    = { instances = 20, pool_size = 2, max_overflow = 1 }
    worker = { instances = 20, pool_size = 1, max_overflow = 1 }
    jobs   = { instances = 11, pool_size = 1, max_overflow = 1 }
  }
}

run "prd_budget_fits" {
  command = plan

  assert {
    condition     = output.total == 142 && output.ceiling == 160
    error_message = "expected 60 + 40 + 22 + 20 = 142 of 160"
  }
  assert {
    condition     = output.env.api.DB_POOL_SIZE == "2" && output.env.api.DB_MAX_OVERFLOW == "1"
    error_message = "env output renders the pool as strings"
  }
}

run "exactly_at_the_ceiling_fits" {
  command = plan

  variables {
    max_connections = 50
    processes       = { api = { instances = 10, pool_size = 1, max_overflow = 1 } }
  }
  assert {
    condition     = output.total == 40 && output.ceiling == 40
    error_message = "10 x 2 + 20 = 40 = 80% of 50"
  }
}

run "app_defaults_exceed_the_budget" {
  command = plan

  # Settings defaults (5 + 10) on 20 api instances: 300 connections against 200.
  variables {
    processes = { api = { instances = 20, pool_size = 5, max_overflow = 10 } }
  }
  expect_failures = [output.env]
}

run "one_connection_over_fails" {
  command = plan

  variables {
    max_connections = 50
    processes       = { api = { instances = 10, pool_size = 1, max_overflow = 1 }, jobs = { instances = 1, pool_size = 1, max_overflow = 1 } }
  }
  expect_failures = [output.env]
}

run "pool_below_two_is_refused" {
  command = plan

  variables {
    processes = { jobs = { instances = 1, pool_size = 1, max_overflow = 0 } }
  }
  expect_failures = [var.processes]
}
