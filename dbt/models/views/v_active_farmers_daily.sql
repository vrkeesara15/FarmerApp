-- AN-001 active farmers trend. Tenant-wide roles only (tenant grain). AN-013: macros/authorised_view.sql
{{ authorised_view('mart_active_farmers_daily', grain='tenant') }}
