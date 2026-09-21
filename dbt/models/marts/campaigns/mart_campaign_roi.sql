{{ config(partition_by=bq_date_partition('week_start')) }}

-- AN-008 campaign ROI: one row per campaign and ISO week of the send (the campaign's channel
-- travels with it; a campaign has exactly one). Mirrors farmerapp.campaigns.service.campaign_roi:
--
--   week_start   Monday of the IST date the recipient was sent to. A holdout was never sent,
--                so its week (like its attribution window) is the campaign start.
--   sent         recipients whose message left FarmerApp (status sent or delivered)
--   delivered    recipients with a delivery receipt (status delivered)
--   opened       recipients with opened_at -- push only (SMS and WhatsApp have no open signal)
--   orders       distinct attributed orders of the TARGET arm, revenue_paise their net sales
--   own_brand_lift  target own-brand share minus holdout own-brand share, NULL when the
--                campaign has no holdout arm or either arm bought nothing in its window
--
-- Attribution (service._arm_outcome), last touch: an order of a recipient placed after that
-- recipient's send and within the campaign's attribution_days of it, unless another campaign
-- reached the same farmer between the send and the order. The holdout arm has no send of its
-- own: its window runs from the campaign start and last touch does not apply to it.
--
-- Two differences from the API, both deliberate: the mart measures money as the net sales of
-- fct_sales_line (fulfilled orders, after the pro-rata order discount, GST excluded) where the
-- API sums order totals, and it keeps the arms' shares per campaign, not per screen. Recipients
-- of a campaign that never started (no send and no started_at) have no week and no row.
with params as (
    select {{ as_of_date() }} as as_of_date
),

campaigns as (
    select * from {{ ref('stg_campaign') }}
),

recipients as (
    select
        r.tenant_id,
        r.campaign_id,
        r.farmer_id,
        r.arm,
        r.status,
        r.is_sent,
        r.sent_at,
        r.opened_at,
        c.channel,
        c.attribution_days,
        coalesce(r.sent_at, c.started_at) as window_start_at,
        {{ week_start(ist_date('coalesce(r.sent_at, c.started_at)')) }} as week_start
    from {{ ref('stg_campaign_recipient') }} as r
    inner join campaigns as c
        on c.campaign_id = r.campaign_id
        and c.tenant_id = r.tenant_id
    where coalesce(r.sent_at, c.started_at) is not null
),

sales as (
    select
        s.tenant_id,
        s.farmer_id,
        s.order_id,
        s.sold_at,
        s.own_brand,
        s.net_paise
    from {{ ref('fct_sales_line') }} as s
    cross join params as p
    where s.farmer_id is not null
        and s.date_day <= p.as_of_date
),

attributed as (
    select
        r.tenant_id,
        r.campaign_id,
        r.week_start,
        r.arm,
        s.order_id,
        s.own_brand,
        s.net_paise
    from recipients as r
    inner join sales as s
        on s.tenant_id = r.tenant_id
        and s.farmer_id = r.farmer_id
        and {{ seconds_between('r.window_start_at', 's.sold_at') }} > 0
        and {{ seconds_between('r.window_start_at', 's.sold_at') }} <= r.attribution_days * 86400
    where case when r.arm = 'target' then r.is_sent else true end
        -- last touch: a later campaign that reached this farmer before the order takes it
        and (
            r.arm <> 'target'
            or not exists (
                select 1
                from {{ ref('stg_campaign_recipient') }} as later
                where later.tenant_id = r.tenant_id
                    and later.farmer_id = r.farmer_id
                    and later.campaign_id <> r.campaign_id
                    and later.is_sent
                    and later.sent_at > r.sent_at
                    and later.sent_at < s.sold_at
            )
        )
),

target_orders as (
    select
        tenant_id,
        campaign_id,
        week_start,
        count(distinct order_id) as orders,
        sum(net_paise) as net_paise,
        sum(case when own_brand then net_paise else 0 end) as own_brand_paise
    from attributed
    where arm = 'target'
    group by tenant_id, campaign_id, week_start
),

holdout_orders as (
    select
        tenant_id,
        campaign_id,
        sum(net_paise) as net_paise,
        sum(case when own_brand then net_paise else 0 end) as own_brand_paise
    from attributed
    where arm = 'holdout'
    group by tenant_id, campaign_id
),

holdout_arm as (
    select tenant_id, campaign_id, count(*) as holdout_size
    from recipients
    where arm = 'holdout'
    group by tenant_id, campaign_id
),

weekly as (
    select
        tenant_id,
        campaign_id,
        channel,
        week_start,
        sum(case when is_sent then 1 else 0 end) as sent,
        sum(case when status = 'delivered' then 1 else 0 end) as delivered,
        sum(case when channel = 'push' and opened_at is not null then 1 else 0 end) as opened
    from recipients
    group by tenant_id, campaign_id, channel, week_start
),

shares as (
    select
        w.tenant_id,
        w.campaign_id,
        w.channel,
        w.week_start,
        w.sent,
        w.delivered,
        w.opened,
        t.orders,
        t.net_paise,
        coalesce(h.holdout_size, 0) as holdout_size,
        {{ safe_ratio('t.own_brand_paise', 't.net_paise') }} as target_own_brand_share,
        {{ safe_ratio('o.own_brand_paise', 'o.net_paise') }} as holdout_own_brand_share
    from weekly as w
    left join target_orders as t
        on t.tenant_id = w.tenant_id
        and t.campaign_id = w.campaign_id
        and t.week_start = w.week_start
    left join holdout_orders as o
        on o.tenant_id = w.tenant_id
        and o.campaign_id = w.campaign_id
    left join holdout_arm as h
        on h.tenant_id = w.tenant_id
        and h.campaign_id = w.campaign_id
)

select
    {{ row_key(['campaign_id', 'week_start']) }} as campaign_week_key,
    tenant_id,
    campaign_id,
    channel,
    week_start,
    cast(sent as {{ dbt.type_bigint() }}) as sent,
    cast(delivered as {{ dbt.type_bigint() }}) as delivered,
    cast(opened as {{ dbt.type_bigint() }}) as opened,
    cast(coalesce(orders, 0) as {{ dbt.type_bigint() }}) as orders,
    {{ paise('net_paise') }} as revenue_paise,
    case when holdout_size > 0
         then round(target_own_brand_share - holdout_own_brand_share, 4) end as own_brand_lift
from shares
