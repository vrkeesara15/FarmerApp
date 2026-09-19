-- AN-006 crop health by district and week. Tenant-wide roles and agronomists.
{{ authorised_view('mart_crop_health_weekly', extra_roles=['agronomist'], grain='tenant') }}
