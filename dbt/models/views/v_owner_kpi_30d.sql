-- AN-001 owner home KPI row. Tenant-wide roles only (tenant grain). AN-013: macros/authorised_view.sql
{{ authorised_view('mart_owner_kpi_30d', grain='tenant') }}
