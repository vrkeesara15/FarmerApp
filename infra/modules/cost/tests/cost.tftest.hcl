# Cost module contract (OPS-012 / NF-015): the human gates hold nothing back that can be
# built without them, the views appear only once the export exists, and the rupee thresholds
# convert to the token / message counts the alerts actually compare against.
# `terraform test` with mock providers, no GCP credentials. Run by infra/scripts/check.sh.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "farmerapp-dev"
  env        = "dev"
}

run "without_the_billing_export_only_the_landing_dataset_exists" {
  command = plan

  assert {
    condition     = google_bigquery_dataset.cost.dataset_id == "farmerapp_cost"
    error_message = "The dataset the Cloud Billing export lands in must exist before the export does; it is what the human points the export at."
  }
  assert {
    condition     = length(google_bigquery_table.views) == 0
    error_message = "A view over the export table cannot be created before the table exists (apply would fail)."
  }
  assert {
    condition     = length(google_bigquery_data_transfer_config.cost_watch) == 0 && length(google_service_account.cost_watch) == 0
    error_message = "The daily cost watch queries the export, so it waits for it too."
  }
  assert {
    condition     = length(google_billing_budget.monthly) == 0
    error_message = "No billing account and no budget amount means no budget resource."
  }
}

run "export_creates_the_service_and_anomaly_views_but_not_the_tenant_split" {
  command = plan

  variables {
    billing_export_table = "gcp_billing_export_resource_v1_0123AB_4567CD_89EF01"
  }

  assert {
    condition = alltrue([for v in [
      "v_cost_daily_by_service", "v_cost_daily_by_sku", "v_cost_daily_total",
      "v_cost_anomaly_daily", "v_cost_monthly_vs_budget",
    ] : contains(keys(google_bigquery_table.views), v)])
    error_message = "SPEC 12.4 wants cost by service; OPS-012 wants the 7-day anomaly; NF-015 wants the month against the budget."
  }
  assert {
    condition     = !contains(keys(google_bigquery_table.views), "v_cost_daily_by_tenant")
    error_message = "Cost by tenant is weighted by the dbt marts, so it waits for marts_dataset."
  }
  assert {
    condition     = length(google_bigquery_data_transfer_config.cost_watch) == 1
    error_message = "With the export in place the daily cost watch must be scheduled."
  }
  assert {
    condition     = strcontains(google_bigquery_data_transfer_config.cost_watch[0].params.query, "RAISE USING MESSAGE")
    error_message = "The watch must fail its run on a breach: the failed run is what the OPS-012 alert watches."
  }
  assert {
    condition     = strcontains(google_bigquery_data_transfer_config.cost_watch[0].params.query, "v_cost_anomaly_daily")
    error_message = "The watch must read the anomaly view, not re-implement the 7-day average."
  }
}

run "tenant_split_needs_the_marts" {
  command = plan

  variables {
    billing_export_table = "gcp_billing_export_resource_v1_0123AB_4567CD_89EF01"
    marts_dataset        = "farmerapp_marts"
  }

  assert {
    condition     = contains(keys(google_bigquery_table.views), "v_cost_daily_by_tenant")
    error_message = "SPEC 12.4 wants cost by tenant once there is something to weight it by."
  }
  assert {
    condition     = strcontains(google_bigquery_table.views["v_cost_daily_by_tenant"].view[0].query, "fct_visit")
    error_message = "The apportionment weight is the tenant's share of the day's visits and order lines."
  }
  assert {
    condition     = strcontains(google_bigquery_table.views["v_cost_daily_by_tenant"].description, "apportionment, not a measurement")
    error_message = "The view must say in its own description that the tenant split is apportioned, so nobody bills a customer from it by accident."
  }
}

run "rate_card_converts_rupee_budgets_into_alert_thresholds" {
  command = plan

  variables {
    llm_daily_inr_per_tenant     = 500
    sms_daily_inr_per_tenant     = 500
    llm_input_inr_per_1k_tokens  = 1.25
    llm_output_inr_per_1k_tokens = 6.25
    sms_inr_per_message          = 0.18
  }

  # A quarter of the daily budget per 6-hour window:
  #   input  500 / 4 / 1.25  * 1000 = 100,000 tokens
  #   output 500 / 4 / 6.25  * 1000 =  20,000 tokens
  #   sms    500 / 4 / 0.18         =     695 messages (ceil)
  assert {
    condition     = output.thresholds.llm_input_tokens_6h == 100000
    error_message = "LLM input threshold must be the rupee budget divided by the rate card, not a magic number."
  }
  assert {
    condition     = output.thresholds.llm_output_tokens_6h == 20000
    error_message = "Output tokens are priced separately, so they get their own condition and threshold."
  }
  assert {
    condition     = output.thresholds.sms_messages_6h == 695
    error_message = "SMS threshold must round up: a partial message is still a whole message."
  }
}

run "spec_12_2_caps_the_daily_ratio_and_the_budget_is_in_rupees" {
  command = plan

  variables {
    billing_account    = "0123AB-4567CD-89EF01"
    monthly_budget_inr = 25000
  }

  assert {
    condition     = var.daily_spend_ratio == 1.3
    error_message = "SPEC 12.2: daily spend above 130% of the 7-day average."
  }
  assert {
    condition     = google_billing_budget.monthly[0].amount[0].specified_amount[0].currency_code == "INR"
    error_message = "NF-015 states the budget in rupees; a budget in another currency would silently compare the wrong number."
  }
  assert {
    condition     = google_billing_budget.monthly[0].amount[0].specified_amount[0].units == "25000"
    error_message = "The pilot budget is Rs 25,000/month (NF-015)."
  }
  assert {
    condition     = length(google_billing_budget.monthly[0].threshold_rules) == 6
    error_message = "Four actual-spend thresholds plus forecast rules for 100% and 130%: a forecast is the only warning that arrives in time to act."
  }
}
