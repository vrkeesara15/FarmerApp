-- AN-009 flag volume and resolution by rule. Tenant-wide roles (owner, director, tenant admin, auditor).
{{ authorised_view('mart_flags_weekly', grain='tenant') }}
