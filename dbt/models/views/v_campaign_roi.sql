-- AN-008 campaign ROI per campaign and ISO week. A campaign belongs to no store or cluster,
-- so the mart is tenant-grain: tenant-wide roles only.
{{ authorised_view('mart_campaign_roi', grain='tenant') }}
