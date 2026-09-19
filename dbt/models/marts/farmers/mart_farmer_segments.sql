-- AN-004 farmers by crop, stage, district and segment (the segment grid of the dashboard):
-- farmers and acreage per tenant x cluster x store x district x crop x stage x segment as of
-- the as-of date. A farmer with two crops counts once under each crop; farmers without a crop
-- plot appear with crop_id / stage NULL and their farm acreage.
with farmers as (
    select * from {{ ref('mart_farmer_360') }}
),

plots as (
    select
        fm.tenant_id,
        fm.farmer_id,
        cp.crop_id,
        cp.stage,
        coalesce(cp.area_acres, 0) as area_acres
    from {{ ref('stg_crop_plot') }} as cp
    inner join {{ ref('stg_farm') }} as fm
        on fm.farm_id = cp.farm_id and fm.tenant_id = cp.tenant_id
),

rows_by_crop as (
    select
        f.tenant_id,
        f.cluster_id,
        f.store_id,
        f.district,
        p.crop_id,
        p.stage,
        f.segment,
        f.as_of_date,
        f.farmer_id,
        coalesce(p.area_acres, f.acreage) as acreage
    from farmers as f
    left join plots as p
        on p.tenant_id = f.tenant_id and p.farmer_id = f.farmer_id
)

select
    {{ row_key(['tenant_id', 'store_id', 'district', 'crop_id', 'stage', 'segment']) }} as segment_key,
    tenant_id,
    cluster_id,
    store_id,
    district,
    crop_id,
    stage,
    segment,
    as_of_date,
    count(distinct farmer_id) as farmers,
    sum(acreage) as acreage
from rows_by_crop
group by tenant_id, cluster_id, store_id, district, crop_id, stage, segment, as_of_date
