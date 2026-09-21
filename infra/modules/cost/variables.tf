variable "project_id" {
  description = "GCP project id of this environment."
  type        = string
}

variable "env" {
  description = "Environment name (dev | stg | prd)."
  type        = string
}

variable "region" {
  description = "Location of the cost dataset (NF-011: keep analytics in asia-south1)."
  type        = string
  default     = "asia-south1"
}

variable "dataset_id" {
  description = "BigQuery dataset that holds the Cloud Billing export and the cost views."
  type        = string
  default     = "farmerapp_cost"
}

# --- Human gates -------------------------------------------------------------------------
# The Cloud Billing export and budgets are configured on the *billing account*, not the
# project, so they need a billing-account admin. Terraform creates the landing dataset and
# everything downstream; a human points the export at it once (docs/runbooks/cost-and-budget.md)
# and then sets `billing_export_table`.

variable "billing_export_table" {
  description = "Table id of the detailed usage-cost export inside `dataset_id` (e.g. gcp_billing_export_resource_v1_0123AB_4567CD_89EF01). Empty until a human enables the export; the views and the daily cost watch are skipped while it is empty."
  type        = string
  default     = ""

  validation {
    condition     = var.billing_export_table == "" || can(regex("^gcp_billing_export_(resource_)?v1_[A-Za-z0-9_]+$", var.billing_export_table))
    error_message = "billing_export_table must be a Cloud Billing export table id (gcp_billing_export_v1_... or gcp_billing_export_resource_v1_...)."
  }
}

variable "billing_account" {
  description = "Billing account id (XXXXXX-XXXXXX-XXXXXX) for the NF-015 budget. Empty = no budget (the daily anomaly watch still runs)."
  type        = string
  default     = ""
}

variable "marts_dataset" {
  description = "dbt marts dataset used to weight the per-tenant split of shared cost. Empty = the by-tenant view is not created."
  type        = string
  default     = ""
}

# --- Thresholds --------------------------------------------------------------------------

variable "daily_spend_ratio" {
  description = "OPS-012: a day's net spend above this multiple of the trailing 7-day average raises the alert (SPEC 12.2: 1.3 = 130%)."
  type        = number
  default     = 1.3

  validation {
    condition     = var.daily_spend_ratio > 1
    error_message = "daily_spend_ratio must be greater than 1 (SPEC 12.2 uses 1.3)."
  }
}

variable "monthly_budget_inr" {
  description = "NF-015: monthly infrastructure budget in rupees (pilot 25,000; 50 stores 1,00,000). 0 = no budget resource."
  type        = number
  default     = 0
}

variable "budget_thresholds" {
  description = "NF-015: fractions of monthly_budget_inr that notify (forecast and actual)."
  type        = list(number)
  default     = [0.5, 0.9, 1.0, 1.3]
}

variable "cost_watch_schedule" {
  description = "Cloud-scheduler-style schedule of the daily cost watch, in UTC (BigQuery Data Transfer syntax). Default 01:30 UTC = 07:00 IST, after the previous day's export has landed."
  type        = string
  default     = "every day 01:30"
}

# --- Rate card (LLM and SMS are not GCP SKUs) --------------------------------------------
# NF-015 excludes SMS and LLM from the infrastructure budget, but OPS-012 still wants "LLM
# and SMS spend by tenant". Neither appears in the billing export: Anthropic and the SMS
# provider bill outside GCP. The per-tenant signal is therefore metered from the API's own
# log lines (`llm_call` carries tenant_id, model, input_tokens, output_tokens; `otp_sent`
# carries tenant_id and channel) and converted to rupees with this rate card, which a human
# keeps in step with the provider contracts.

variable "llm_input_inr_per_1k_tokens" {
  description = "Rate card: rupees per 1,000 LLM input tokens (claude-opus-5 list price at the pilot USD rate; docs/cost-model.md)."
  type        = number
  default     = 1.25
}

variable "llm_output_inr_per_1k_tokens" {
  description = "Rate card: rupees per 1,000 LLM output tokens."
  type        = number
  default     = 6.25
}

variable "sms_inr_per_message" {
  description = "Rate card: rupees per transactional SMS (DLT-registered OTP template)."
  type        = number
  default     = 0.18
}

variable "llm_daily_inr_per_tenant" {
  description = "OPS-012: LLM spend for one tenant in a day that notifies the owner and platform lead."
  type        = number
  default     = 500
}

variable "sms_daily_inr_per_tenant" {
  description = "OPS-012: SMS spend for one tenant in a day that notifies the owner and platform lead."
  type        = number
  default     = 500
}

# --- Alerting ----------------------------------------------------------------------------

variable "notification_channels" {
  description = "Channel ids per severity, from modules/monitoring's `notification_channels` output."
  type = object({
    sev1 = list(string)
    sev2 = list(string)
    sev3 = list(string)
  })
  default = { sev1 = [], sev2 = [], sev3 = [] }
}

variable "runbook_base_url" {
  description = "Base URL of docs/runbooks, linked from every alert."
  type        = string
  default     = "docs/runbooks"
}

variable "alerts_enabled" {
  description = "Create the OPS-012 alert policies."
  type        = bool
  default     = true
}

variable "budget_topic" {
  description = "Pub/Sub topic the budget publishes threshold notifications to."
  type        = string
  default     = "cost.budget"
}
