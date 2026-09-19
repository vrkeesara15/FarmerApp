-- SPEC 5.2 "Credit overdue" per farmer x store ledger (khata account) as of the as-of date:
-- entries written up to the end of that IST day, credits settling the debits due first
-- (farmerapp.khata.aging.open_debits). FIFO in closed form, as the API's credit_by_farmer:
--   open part of the debits due before D = max(sum(debits due before D) - credits, 0)
-- so with O(k) = that amount for D = as_of - k days:
--   0_30 = O(0) - O(30), 31_60 = O(30) - O(60), 61_90 = O(60) - O(90), 90_plus = O(90)
-- (days overdue 1-30 fall in 0_30: a debit is overdue from the day after its due date).
-- Only accounts with an open balance are kept (kpi.credit_book "accounts").
with params as (
    select {{ as_of_date() }} as as_of_date
),

entries as (
    select k.*
    from {{ ref('stg_khata_entry') }} as k
    cross join params as p
    where k.created_date <= p.as_of_date
),

accounts as (
    select
        e.tenant_id,
        e.store_id,
        e.farmer_id,
        sum(case when e.entry_type = 'debit' then e.amount_paise else 0 end) as debits_paise,
        sum(case when e.entry_type = 'credit' then e.amount_paise else 0 end) as credits_paise,
        {% for k in [0, 30, 60, 90] %}
        sum(case when e.entry_type = 'debit' and e.effective_due_date < {{ add_days('p.as_of_date', -k) }}
                 then e.amount_paise else 0 end) as due_before_{{ k }}_paise{{ "," if not loop.last }}
        {% endfor %}
    from entries as e
    cross join params as p
    group by e.tenant_id, e.store_id, e.farmer_id
),

aged as (
    select
        a.*,
        greatest(a.debits_paise - a.credits_paise, 0) as outstanding_paise,
        {% for k in [0, 30, 60, 90] %}
        greatest(a.due_before_{{ k }}_paise - a.credits_paise, 0) as open_{{ k }}{{ "," if not loop.last }}
        {% endfor %}
    from accounts as a
)

select
    {{ row_key(['a.tenant_id', 'a.store_id', 'a.farmer_id']) }} as credit_account_key,
    a.tenant_id,
    s.cluster_id,
    a.store_id,
    a.farmer_id,
    p.as_of_date,
    a.debits_paise,
    a.credits_paise,
    a.outstanding_paise,
    a.open_0 as overdue_paise,
    a.open_0 - a.open_30 as overdue_0_30_paise,
    a.open_30 - a.open_60 as overdue_31_60_paise,
    a.open_60 - a.open_90 as overdue_61_90_paise,
    a.open_90 as overdue_90_plus_paise,
    -- kpi.credit_risk: high = anything more than 60 days overdue; medium = overdue at all
    case
        when a.open_60 > 0 then 'high'
        when a.open_0 > 0 then 'medium'
        else 'low'
    end as credit_risk
from aged as a
cross join params as p
left join {{ ref('dim_store') }} as s
    on s.store_id = a.store_id
    and s.tenant_id = a.tenant_id
where a.outstanding_paise > 0
