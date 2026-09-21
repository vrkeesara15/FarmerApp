# Connection budget precondition (outputs.tf): `terraform test`, no providers or credentials.
# Run by infra/scripts/check.sh and ci-infra.yml.

# The default fixture is prd as envs/prd/terraform.tfvars has it (M7: 17 Cloud Run jobs,
# sql_max_connections raised 200 -> 250 so four more jobs still fit).
variables {
  max_connections = 250
  processes = {
    api    = { instances = 20, pool_size = 2, max_overflow = 1 }
    worker = { instances = 20, pool_size = 2, max_overflow = 0 }
    jobs   = { instances = 17, pool_size = 1, max_overflow = 1 }
  }
}

run "prd_budget_fits" {
  command = plan

  assert {
    condition     = output.total == 154 && output.ceiling == 200
    error_message = "expected 60 + 40 + 34 + 20 = 154 of 200"
  }
  assert {
    condition     = output.env.api.DB_POOL_SIZE == "2" && output.env.api.DB_MAX_OVERFLOW == "1"
    error_message = "env output renders the pool as strings"
  }
}

# docs/deploy/configuration.md "Connection budget": every environment keeps room for at least
# four more Cloud Run jobs, so the next feature loop does not have to touch the flag again.
run "four_more_jobs_still_fit_in_prd" {
  command = plan

  variables {
    processes = {
      api    = { instances = 20, pool_size = 2, max_overflow = 1 }
      worker = { instances = 20, pool_size = 2, max_overflow = 0 }
      jobs   = { instances = 21, pool_size = 1, max_overflow = 1 }
    }
  }
  assert {
    condition     = output.total == 162 && output.ceiling == 200
    error_message = "21 jobs: 60 + 40 + 42 + 20 = 162 of 200"
  }
}

run "four_more_jobs_still_fit_in_stg" {
  command = plan

  variables {
    max_connections = 125
    processes = {
      api    = { instances = 5, pool_size = 2, max_overflow = 1 }
      worker = { instances = 5, pool_size = 2, max_overflow = 0 }
      jobs   = { instances = 21, pool_size = 1, max_overflow = 1 }
    }
  }
  assert {
    condition     = output.total == 87 && output.ceiling == 100
    error_message = "stg with 21 jobs: 15 + 10 + 42 + 20 = 87 of 100"
  }
}

run "four_more_jobs_still_fit_in_dev" {
  command = plan

  variables {
    max_connections = 100
    processes = {
      api    = { instances = 3, pool_size = 2, max_overflow = 1 }
      worker = { instances = 2, pool_size = 2, max_overflow = 0 }
      jobs   = { instances = 21, pool_size = 1, max_overflow = 1 }
    }
  }
  assert {
    condition     = output.total == 75 && output.ceiling == 80
    error_message = "dev with 21 jobs: 9 + 4 + 42 + 20 = 75 of 80"
  }
}

# The old stg shape (17 jobs at max_connections 100) was one job from the ceiling: four more
# jobs did not fit, which is why the flag was raised.
run "stg_before_the_raise_cannot_take_four_more_jobs" {
  command = plan

  variables {
    max_connections = 100
    processes = {
      api    = { instances = 5, pool_size = 2, max_overflow = 1 }
      worker = { instances = 5, pool_size = 2, max_overflow = 0 }
      jobs   = { instances = 21, pool_size = 1, max_overflow = 1 }
    }
  }
  expect_failures = [output.env]
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

  # Settings defaults (5 + 10) on 20 api instances: 300 connections against 250.
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

# NF-007 (docs/perf/NF-007.md): 50 tenants add no pools — a pool belongs to a process, not a
# tenant — but they add concurrent requests, so the api / worker ceilings rise. At the SaaS
# shape (api 60, worker 40, today's 17 jobs) prd's current 250 is not enough and the plan says
# *before* an apply exhausts Cloud SQL. Raising sql_max_connections restarts the instance, so
# it stays a human gate in a maintenance window (docs/deploy/configuration.md).
run "saas_shape_needs_a_bigger_flag" {
  command = plan

  variables {
    processes = {
      api    = { instances = 60, pool_size = 2, max_overflow = 1 }
      worker = { instances = 40, pool_size = 2, max_overflow = 0 }
      jobs   = { instances = 17, pool_size = 1, max_overflow = 1 }
    }
  }
  expect_failures = [output.env]
}

run "saas_shape_fits_at_500_connections" {
  command = plan

  variables {
    max_connections = 500
    processes = {
      api    = { instances = 60, pool_size = 2, max_overflow = 1 }
      worker = { instances = 40, pool_size = 2, max_overflow = 0 }
      jobs   = { instances = 17, pool_size = 1, max_overflow = 1 }
    }
  }
  assert {
    condition     = output.total == 314 && output.ceiling == 400
    error_message = "SaaS shape: 180 + 80 + 34 + 20 = 314 of 400"
  }
}
