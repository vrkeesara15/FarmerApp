-- AN-008 campaign ROI -- PLACEHOLDER until WC-008 (campaigns) exists in the API: there is no
-- campaign table to replicate yet, so this mart has the final shape (campaign x channel x ISO
-- week) and no rows. The authorised view and the console can be built against it now; when
-- WC-008 lands, replace the body with sent / delivered / opened from the campaign's
-- notifications and orders / revenue / own-brand lift from fct_sales_line within the
-- attribution window. The tests in _marts.yml already hold for the real rows.
select
    cast(null as {{ dbt.type_string() }}) as campaign_week_key,
    t.tenant_id,
    cast(null as {{ dbt.type_string() }}) as campaign_id,
    cast(null as {{ dbt.type_string() }}) as channel,
    cast(null as date) as week_start,
    cast(0 as {{ dbt.type_bigint() }}) as sent,
    cast(0 as {{ dbt.type_bigint() }}) as delivered,
    cast(0 as {{ dbt.type_bigint() }}) as opened,
    cast(0 as {{ dbt.type_bigint() }}) as orders,
    cast(0 as {{ dbt.type_bigint() }}) as revenue_paise,
    cast(null as {{ type_double() }}) as own_brand_lift
from {{ ref('stg_tenant') }} as t
where 1 = 0
