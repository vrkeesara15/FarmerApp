-- AN-007 diagnosis quality. Tenant-wide roles and agronomists.
{{ authorised_view('mart_diagnosis_quality_weekly', extra_roles=['agronomist'], grain='tenant') }}
