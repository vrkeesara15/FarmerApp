# Monitoring module contract for the M7 monitors (OPS-011, OPS-013, OPS-014), and the two
# invariants SPEC 12 states about *every* alert: a severity that maps to the right channels,
# and an owner + runbook in its documentation.
# `terraform test` with mock providers, no GCP credentials. Run by infra/scripts/check.sh.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "farmerapp-dev"
  env        = "dev"
  # No e-mail channel: its id is only known after apply, and these assertions are
  # about routing by severity, which the channel lists already prove.
  notification_email = ""
  page_channels      = ["projects/farmerapp-dev/notificationChannels/page"]
  ticket_channels    = ["projects/farmerapp-dev/notificationChannels/ticket"]
  digest_channels    = ["projects/farmerapp-dev/notificationChannels/digest"]
  runbook_base_url   = "https://example.invalid/runbooks"
  uptime_checks = {
    api     = { host = "api.dev.farmerapp.in", path = "/v1/health" }
    console = { host = "console.dev.farmerapp.in", path = "/login" }
  }
}

# --- OPS-011 ------------------------------------------------------------------------------

run "ops_011_dbt_and_datastream" {
  command = plan

  variables {
    datastream_stream_ids = ["farmerapp-dev-cdc"]
  }

  assert {
    condition     = google_logging_metric.dbt_failed.filter == "(logName=\"projects/farmerapp-dev/logs/dbt\" OR (resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"dbt\")) AND jsonPayload.event=\"dbt_run_failed\""
    error_message = "The dbt failure metric must read the wrapper's own log (dbt/scripts/dbt_run.py) as well as a dbt run inside a Cloud Run job."
  }
  assert {
    condition     = length(google_monitoring_alert_policy.dbt_failed) == 1 && length(google_monitoring_alert_policy.dbt_source_stale) == 1
    error_message = "SPEC 12.2 OPS-011 is two signals: a failed run or test, and a stale source."
  }
  assert {
    condition     = google_monitoring_alert_policy.dbt_failed[0].user_labels.owner == "data-owner"
    error_message = "SPEC 12.2 routes OPS-011 to the data owner, not the platform lead."
  }
  assert {
    condition     = google_monitoring_alert_policy.datastream_freshness["farmerapp-dev-cdc"].conditions[0].condition_threshold[0].threshold_value == 1800
    error_message = "SPEC 12.2: Datastream lag > 30 min (1800 s)."
  }
  assert {
    condition     = google_monitoring_alert_policy.dbt_failed[0].notification_channels == tolist(["projects/farmerapp-dev/notificationChannels/ticket"])
    error_message = "Sev 2 goes to the ticket channel and not to the pager (SPEC 12.3)."
  }
}

run "ops_011_datastream_alerts_wait_for_a_stream" {
  command = plan

  assert {
    condition     = length(google_monitoring_alert_policy.datastream_freshness) == 0
    error_message = "With no stream id (dev before datastream_stream_enabled) there is nothing to watch, and an alert on a non-existent stream is noise."
  }
  assert {
    condition     = length(google_monitoring_alert_policy.dbt_failed) == 1
    error_message = "The dbt half of OPS-011 does not depend on Datastream: CI runs dbt long before the stream exists."
  }
}

# --- OPS-013 ------------------------------------------------------------------------------

run "ops_013_pages_on_all_three_signals" {
  command = plan

  assert {
    condition = alltrue([
      length(google_monitoring_alert_policy.scc_high) == 1,
      length(google_monitoring_alert_policy.armor_spike) == 1,
      length(google_monitoring_alert_policy.otp_spike) == 1,
    ])
    error_message = "SPEC 12.2 OPS-013 names three signals: SCC high findings, Cloud Armor spikes, OTP send spikes."
  }
  assert {
    condition = alltrue([
      google_monitoring_alert_policy.scc_high[0].user_labels.sev == "sev1",
      google_monitoring_alert_policy.armor_spike[0].user_labels.sev == "sev1",
      google_monitoring_alert_policy.otp_spike[0].user_labels.sev == "sev1",
    ])
    error_message = "SPEC 12.2 OPS-013 action is 'page on-call', which is Sev 1 in 12.3."
  }
  assert {
    condition     = contains(google_monitoring_alert_policy.otp_spike[0].notification_channels, "projects/farmerapp-dev/notificationChannels/page")
    error_message = "A Sev 1 must reach the paging channel."
  }
  assert {
    condition     = strcontains(google_monitoring_alert_policy.otp_spike[0].conditions[0].condition_threshold[0].aggregations[0].group_by_fields[0], "tenant_id")
    error_message = "SMS pumping hits one tenant; grouping by tenant is what makes the spike visible."
  }
  assert {
    condition     = strcontains(google_logging_metric.armor_denied.filter, "enforcedSecurityPolicy.outcome=\"DENY\"")
    error_message = "A blocked request is a DENY outcome in the load balancer's request log (modules/lb enables logging)."
  }
}

# --- OPS-014 ------------------------------------------------------------------------------

run "ops_014_certificates_and_secret_age" {
  command = plan

  assert {
    condition     = length(google_monitoring_alert_policy.cert_expiry) == 2
    error_message = "One certificate alert per checked host, off the uptime check that already validates SSL."
  }
  assert {
    condition     = google_monitoring_alert_policy.cert_expiry["api"].conditions[0].condition_threshold[0].threshold_value == 21
    error_message = "SPEC 12.2: certificate expiry < 21 days."
  }
  assert {
    condition     = google_monitoring_alert_policy.cert_expiry["api"].conditions[0].condition_threshold[0].comparison == "COMPARISON_LT"
    error_message = "Days remaining falls towards the threshold, so the comparison is less-than."
  }
  assert {
    condition     = length(google_monitoring_alert_policy.secret_age) == 1
    error_message = "SPEC 12.2: secret age > 90 days raises a ticket. The signal is Secret Manager's own rotation reminder (modules/secrets owns the topic)."
  }
  assert {
    condition     = google_monitoring_alert_policy.secret_age[0].user_labels.sev == "sev2"
    error_message = "OPS-014 is a ticket, not a page."
  }
}

run "ops_014_without_a_rotation_topic_there_is_no_secret_alert" {
  command = plan

  variables {
    secret_rotation_topic = ""
  }

  assert {
    condition     = length(google_monitoring_alert_policy.secret_age) == 0
    error_message = "No topic means Secret Manager publishes nothing, so an alert on it would never fire and would lie about coverage."
  }
}

# --- SPEC 12 invariants -------------------------------------------------------------------

run "every_alert_names_an_owner_a_severity_and_a_runbook" {
  command = plan

  variables {
    datastream_stream_ids = ["farmerapp-dev-cdc"]
    pubsub_topics         = ["payment.webhook", "visit.created"]
    jobs                  = { migrate = { owner = "platform-lead", description = "Alembic upgrade head" } }
    sql_instance_id       = "farmerapp-dev:farmerapp-dev"
  }

  assert {
    condition = alltrue([
      for p in concat(
        values(google_monitoring_alert_policy.uptime), values(google_monitoring_alert_policy.error_rate),
        google_monitoring_alert_policy.app_errors, values(google_monitoring_alert_policy.sql),
        values(google_monitoring_alert_policy.pubsub_backlog), values(google_monitoring_alert_policy.pubsub_dlq),
        values(google_monitoring_alert_policy.job_failed), google_monitoring_alert_policy.dbt_failed,
        google_monitoring_alert_policy.dbt_source_stale, values(google_monitoring_alert_policy.datastream_freshness),
        values(google_monitoring_alert_policy.datastream_unsupported), google_monitoring_alert_policy.scc_high,
        google_monitoring_alert_policy.armor_spike, google_monitoring_alert_policy.otp_spike,
        values(google_monitoring_alert_policy.cert_expiry), google_monitoring_alert_policy.secret_age,
      ) : contains(keys(p.user_labels), "owner") && contains(keys(p.user_labels), "sev") && contains(keys(p.user_labels), "ops")
    ])
    error_message = "SPEC 12: every alert has an owner, a severity and the OPS id it serves."
  }

  assert {
    condition = alltrue([
      for p in concat(
        google_monitoring_alert_policy.dbt_failed, google_monitoring_alert_policy.dbt_source_stale,
        values(google_monitoring_alert_policy.datastream_freshness), google_monitoring_alert_policy.scc_high,
        google_monitoring_alert_policy.armor_spike, google_monitoring_alert_policy.otp_spike,
        values(google_monitoring_alert_policy.cert_expiry), google_monitoring_alert_policy.secret_age,
      ) : strcontains(p.documentation[0].content, "https://example.invalid/runbooks")
    ])
    error_message = "SPEC 12: every alert links the runbook that says what to do about it."
  }
}
