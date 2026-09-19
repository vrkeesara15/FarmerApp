"""Analytics read API (M4: AN-001, AN-002, AN-003, AN-011; WC-001 .. WC-004).

SPEC 5.3: for P0 the console reads the live (read-replica) Postgres tables; BigQuery and dbt
arrive in P1. Everything here is read-only and scoped per the SPEC 2.6 matrix:

* ``filters`` — the AN-011 filter set (``from``, ``to``, ``cluster_id``, ``store_id``,
  ``officer_id``, ``crop_id``) as a FastAPI dependency, and ``resolve_scope`` which narrows it
  by the caller's role (cluster head -> own cluster, store manager -> own store, field
  officer -> own figures) and rejects invalid combinations (422).
* ``kpi`` — the SPEC 5.2 KPI definitions as pure functions over small fact records.
* ``facts`` — SQL loaders that turn the live tables into those records.
* ``ports`` — ``FlagCountsPort``: open validation flags (VA-*) come from the flags branch;
  until it lands the null adapter answers zeros.
* ``owner_home`` / ``field_team`` / ``replay`` / ``farmers`` / ``stores`` — one module per
  console screen (C10, C20-C22, C30-C31, C40-C41); ``router`` exposes them.
"""
