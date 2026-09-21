# SPEC 12.4 "Cost: by service and by tenant", as BigQuery views over the Cloud Billing
# export. Cloud Monitoring cannot query BigQuery, so the rupee figures live here and in
# Looker Studio; the Monitoring cost dashboard (modules/monitoring/dashboards.tf) carries
# the usage drivers and links to these views.
#
# Net cost everywhere = `cost` + every credit on the row (committed-use discounts, free
# tier, promotions). Gross cost flatters nobody and free-tier-heavy environments like dev
# would read as costing several times what they bill.
#
# Every view is created only when `billing_export_table` is set, because a view over a
# table that does not exist fails at apply time, and the export is a human gate.

locals {
  # `labels` on a billing row are the resource's labels at the time of use.
  label = "(SELECT value FROM UNNEST(labels) WHERE key = '%s')"

  net_cost = "SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0))"

  views = local.export_ready ? merge({
    # --- by service ------------------------------------------------------------------
    v_cost_daily_by_service = {
      description = "OPS-012 / SPEC 12.4: net spend per IST day per GCP service and labelled component."
      query       = <<-SQL
        SELECT
          DATE(usage_start_time, 'Asia/Kolkata')                  AS day,
          service.description                                     AS service,
          COALESCE(${format(local.label, "component")}, 'unlabelled') AS component,
          COALESCE(${format(local.label, "tenancy")}, 'shared')    AS tenancy,
          currency,
          ${local.net_cost}                                       AS net_cost
        FROM ${local.export_ref}
        WHERE project.id = '${var.project_id}'
        GROUP BY day, service, component, tenancy, currency
      SQL
    }

    v_cost_daily_by_sku = {
      description = "The same spend one level down: per SKU, for working out which knob to turn."
      query       = <<-SQL
        SELECT
          DATE(usage_start_time, 'Asia/Kolkata') AS day,
          service.description                    AS service,
          sku.description                        AS sku,
          ANY_VALUE(usage.pricing_unit)          AS pricing_unit,
          SUM(usage.amount_in_pricing_units)     AS usage_amount,
          currency,
          ${local.net_cost}                      AS net_cost
        FROM ${local.export_ref}
        WHERE project.id = '${var.project_id}'
        GROUP BY day, service, sku, currency
      SQL
    }

    # --- daily total and the OPS-012 anomaly -----------------------------------------
    v_cost_daily_total = {
      description = "OPS-012: net spend per IST day for this project."
      query       = <<-SQL
        SELECT
          DATE(usage_start_time, 'Asia/Kolkata') AS day,
          currency,
          ${local.net_cost} AS net_cost
        FROM ${local.export_ref}
        WHERE project.id = '${var.project_id}'
        GROUP BY day, currency
      SQL
    }

    v_cost_anomaly_daily = {
      description = "OPS-012: each day's net spend against the average of the 7 days before it. `ratio` > ${var.daily_spend_ratio} is the alert condition; the first 7 days have no average and are never a breach."
      query       = <<-SQL
        SELECT
          day,
          currency,
          net_cost,
          AVG(net_cost) OVER w AS avg_7d,
          SAFE_DIVIDE(net_cost, AVG(net_cost) OVER w) AS ratio,
          ${var.daily_spend_ratio} AS threshold
        FROM `${var.project_id}.${var.dataset_id}.v_cost_daily_total`
        WINDOW w AS (
          PARTITION BY currency ORDER BY UNIX_DATE(day)
          RANGE BETWEEN 7 PRECEDING AND 1 PRECEDING
        )
      SQL
    }

    # --- monthly, against the NF-015 budget ------------------------------------------
    v_cost_monthly_vs_budget = {
      description = "NF-015: month-to-date net spend against the ${var.monthly_budget_inr > 0 ? format("Rs %d", var.monthly_budget_inr) : "configured"} monthly budget."
      query       = <<-SQL
        SELECT
          invoice.month AS invoice_month,
          currency,
          ${local.net_cost} AS net_cost,
          ${var.monthly_budget_inr} AS budget_inr,
          SAFE_DIVIDE(${local.net_cost}, NULLIF(${var.monthly_budget_inr}, 0)) AS budget_share
        FROM ${local.export_ref}
        WHERE project.id = '${var.project_id}'
        GROUP BY invoice_month, currency
      SQL
    }
    },

    # --- by tenant -------------------------------------------------------------------
    # Shared cost apportioned by each tenant's share of the day's billable activity. The
    # weight is visits + order lines, the two things that actually drive load (writes,
    # sync, photos, reads behind them) and the two the marts already model per tenant and
    # per IST day.
    #
    # Limits, in the view's own description and in docs/cost-model.md:
    #  * it is an apportionment, not a measurement. A tenant that only *reads* pays its
    #    share of a bill it did not create; a tenant whose officers upload 4x the photos
    #    pays the same per visit as one whose officers upload none.
    #  * `tenancy = dedicated` rows are billed to their tenant directly (via the
    #    `tenant_id` label) and excluded from the shared pool, so the split keeps working
    #    when a large tenant gets its own service.
    #  * a day with no activity at all is split equally between the tenants that existed.
    #  * LLM and SMS are not here at all: different vendors, no billing export. They are
    #    metered per tenant in Cloud Monitoring and alerted in alerts.tf.
    local.tenant_ready ? {
      v_cost_daily_by_tenant = {
        description = "SPEC 12.4 cost by tenant: dedicated resources billed directly, shared cost apportioned by the tenant's share of the day's visits + order lines. An apportionment, not a measurement - see infra/modules/cost/views.tf and docs/cost-model.md. Excludes LLM and SMS (not GCP SKUs)."
        query       = <<-SQL
          WITH billed AS (
            SELECT
              DATE(usage_start_time, 'Asia/Kolkata') AS day,
              ${format(local.label, "tenant_id")}    AS tenant_id,
              COALESCE(${format(local.label, "tenancy")}, 'shared') AS tenancy,
              currency,
              ${local.net_cost} AS net_cost
            FROM ${local.export_ref}
            WHERE project.id = '${var.project_id}'
            GROUP BY day, tenant_id, tenancy, currency
          ),
          dedicated AS (
            SELECT day, tenant_id, currency, SUM(net_cost) AS direct_cost
            FROM billed
            WHERE tenancy = 'dedicated' AND tenant_id IS NOT NULL
            GROUP BY day, tenant_id, currency
          ),
          shared AS (
            SELECT day, currency, SUM(net_cost) AS shared_cost
            FROM billed
            WHERE tenancy != 'dedicated' OR tenant_id IS NULL
            GROUP BY day, currency
          ),
          activity AS (
            SELECT tenant_id, date_day AS day, COUNT(*) AS units
            FROM `${var.project_id}.${var.marts_dataset}.fct_visit`
            GROUP BY tenant_id, day
            UNION ALL
            SELECT tenant_id, date_day AS day, COUNT(*) AS units
            FROM `${var.project_id}.${var.marts_dataset}.fct_sales_line`
            GROUP BY tenant_id, day
          ),
          weights AS (
            SELECT
              day,
              tenant_id,
              SUM(units) AS units,
              SAFE_DIVIDE(SUM(units), SUM(SUM(units)) OVER (PARTITION BY day)) AS share
            FROM activity
            GROUP BY day, tenant_id
          )
          SELECT
            s.day,
            w.tenant_id,
            s.currency,
            IFNULL(d.direct_cost, 0)                       AS direct_cost,
            s.shared_cost * IFNULL(w.share, 0)             AS apportioned_cost,
            IFNULL(d.direct_cost, 0) + s.shared_cost * IFNULL(w.share, 0) AS net_cost,
            IFNULL(w.units, 0)                             AS activity_units,
            IFNULL(w.share, 0)                             AS activity_share
          FROM shared s
          LEFT JOIN weights w ON w.day = s.day
          LEFT JOIN dedicated d ON d.day = s.day AND d.tenant_id = w.tenant_id AND d.currency = s.currency
        SQL
      }
  } : {}) : {}
}

resource "google_bigquery_table" "views" {
  for_each = local.views

  # checkov:skip=CKV_GCP_121:A view stores no rows. Its whole content is the query above,
  # which lives in Terraform; deletion protection would only make renaming a view a
  # two-apply dance while protecting nothing.
  # checkov:skip=CKV_GCP_80:Same accepted baseline as CKV_GCP_81 in .checkov.yaml --
  # Google-managed encryption at rest. A CSEK view over a Google-managed export table would
  # not encrypt anything extra; CMEK across BigQuery is revisited with SEC-026.
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.cost.dataset_id
  table_id            = each.key
  description         = each.value.description
  deletion_protection = false
  labels              = local.labels

  view {
    query          = each.value.query
    use_legacy_sql = false
  }
}
