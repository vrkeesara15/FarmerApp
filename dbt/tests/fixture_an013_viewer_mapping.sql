{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-013']) }}
{#
  AN-013 mapping on the fixtures: exactly which stores each viewer sees in v_store_snapshot,
  and who sees the agronomy view. Any difference (a missing or an extra row) fails.
    u-owner, u-dir, u-admin, u-aud   all t1 stores s1, s2, s3
    u-ch1  cluster head of c1 (its OLDER CDC row said c2: the latest row wins) -> s1, s2
    u-ch2  cluster head of c2 -> s3
    u-sm1  store manager of s1 -> s1
    u2-owner (t2) -> s4 only
    nobody else: field officers, accountant, agronomist (not a store-view role), the farmer
    login, the disabled store manager u-sm-off, the deleted owner u-gone
  v_crop_health_weekly (3 t1 rows): tenant-wide roles and the agronomist, not cluster heads.
#}
{% set store_expected = {
    'u-owner': ['s1', 's2', 's3'], 'u-dir': ['s1', 's2', 's3'], 'u-admin': ['s1', 's2', 's3'],
    'u-aud': ['s1', 's2', 's3'], 'u-ch1': ['s1', 's2'], 'u-ch2': ['s3'], 'u-sm1': ['s1'],
    'u2-owner': ['s4'],
} %}
{% set crop_viewers = ['u-owner', 'u-dir', 'u-admin', 'u-aud', 'u-agro'] %}

with expected_store as (
    {% for viewer, stores in store_expected.items() %}
    {% set outer = loop %}
    {% for store in stores %}
    select '{{ viewer }}' as viewer_user_id, '{{ store }}' as store_id
    {{ "union all" if not (loop.last and outer.last) }}
    {% endfor %}
    {% endfor %}
),

actual_store as (
    select viewer_user_id, store_id from {{ ref('v_store_snapshot') }}
),

store_diff as (
    select coalesce(e.viewer_user_id, a.viewer_user_id) as viewer_user_id,
           coalesce(e.store_id, a.store_id) as subject,
           case when a.viewer_user_id is null then 'missing row' else 'row outside scope' end as problem
    from expected_store as e
    full outer join actual_store as a
        on a.viewer_user_id = e.viewer_user_id and a.store_id = e.store_id
    where e.viewer_user_id is null or a.viewer_user_id is null
),

crop_counts as (
    select viewer_user_id, count(*) as n
    from {{ ref('v_crop_health_weekly') }}
    group by viewer_user_id
),

expected_crop as (
    {% for viewer in crop_viewers %}
    select '{{ viewer }}' as viewer_user_id, 3 as n {{ "union all" if not loop.last }}
    {% endfor %}
),

crop_diff as (
    select coalesce(e.viewer_user_id, a.viewer_user_id) as viewer_user_id,
           'v_crop_health_weekly' as subject,
           'crop view rows differ' as problem
    from expected_crop as e
    full outer join crop_counts as a on a.viewer_user_id = e.viewer_user_id
    where e.viewer_user_id is null or a.viewer_user_id is null or a.n <> e.n
)

select * from store_diff
union all
select * from crop_diff
