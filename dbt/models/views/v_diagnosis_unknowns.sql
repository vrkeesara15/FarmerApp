-- AN-007 top unknowns. Tenant-wide roles and agronomists.
{{ authorised_view('mart_diagnosis_unknowns', extra_roles=['agronomist'], grain='tenant') }}
