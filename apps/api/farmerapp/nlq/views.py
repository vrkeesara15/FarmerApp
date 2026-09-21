"""AN-016: the authorised views, the read-only role, and the schema the model is shown.

One module is the single source of truth for three consumers:

* **Alembic ``0043``** creates :data:`VIEWS` and the ``farmerapp_readonly`` role from
  :func:`ddl_statements` / :func:`role_statements`.
* **The validator** (:mod:`farmerapp.nlq.sql_guard`) allows exactly :data:`VIEW_NAMES` and
  nothing else — no table, no other schema, no function outside its own allowlist.
* **The prompt** (:mod:`farmerapp.nlq.llm`) is built from :func:`schema_text`, which is column
  names and descriptions only: **never a row, never a value** (SEC-027).

Why Postgres views and not the BigQuery ``farmerapp_views`` dataset
-------------------------------------------------------------------
SPEC 5.3: "for P0 the console reads read-only Postgres replicas for live figures; BigQuery
and dbt arrive in P1". The dbt authorised views (``dbt/models/views/v_*``, AN-013) are the
same idea one layer up, with the same grains, names and scope rules — when the console moves
to BigQuery these definitions move with it. Until then AN-016 asks the database the console
already reads, so the answer and the dashboard can never disagree.

How "authorised" is enforced, in four independent layers
--------------------------------------------------------
1. **The role.** The query runs as ``farmerapp_readonly`` (``SET LOCAL ROLE``), which is
   ``NOLOGIN NOBYPASSRLS`` and has been granted ``SELECT`` on **these five views and nothing
   else** — no table, no sequence, no other view. It has no INSERT/UPDATE/DELETE anywhere, so
   a write that somehow reached the database would fail on privileges.
2. **The transaction.** ``SET LOCAL transaction_read_only = on`` plus a
   ``statement_timeout``; the whole thing runs in a savepoint that is always rolled back.
3. **The view bodies.** Every view filters ``tenant_id = app_current_tenant()`` (the same
   binding Postgres RLS uses) and calls :func:`app_nlq_scope_ok`, which reads the caller's
   scope from two GUCs the request sets. A cluster head's question can therefore only ever
   return their own cluster's rows **whatever SQL the model wrote**.
4. **The validator**, before any of that: a single ``SELECT``, allowlisted relations,
   allowlisted functions, no DDL/DML, no CTE-based write, no ``pg_*`` or
   ``information_schema``.

PII
---
Farmer identity never enters a view: no farmer name, phone, landmark, coordinate or village
point (AN-014). Employee *names* do appear in ``v_officer_week``, because the question the
spec gives as the acceptance criterion ("which officers had fewer than 3 verified visits last
week?") is unanswerable without them and the three roles allowed to ask are exactly the roles
that already see officer names in the console (WC-002). Those rows go to the caller and **to
nobody else**: the prompt carries :func:`schema_text` and the caller's scope, never a row.
"""

from __future__ import annotations

from dataclasses import dataclass

from farmerapp.db.rls import APP_ROLE, MIGRATE_ROLE, TENANT_FUNCTION

#: The read-only database role AN-016 queries run as.
READONLY_ROLE = "farmerapp_readonly"

#: GUCs that carry the caller's scope into the view bodies (empty = tenant-wide).
CLUSTER_SETTING = "app.nlq_cluster_id"
STORE_SETTING = "app.nlq_store_id"
SCOPE_FUNCTION = "app_nlq_scope_ok"


@dataclass(frozen=True)
class View:
    """One authorised view: its name, what it means, its grain and its columns."""

    name: str
    grain: str
    description: str
    columns: tuple[tuple[str, str], ...]
    sql: str
    #: True when the view carries ``cluster_id`` / ``store_id`` and is therefore scoped.
    scoped: bool = True


_TENANT = f"tenant_id = {TENANT_FUNCTION}()"

# --------------------------------------------------------------------------- v_officer_week
_OFFICER_WEEK = View(
    name="v_officer_week",
    grain="one row per field officer per ISO week (IST)",
    description=(
        "Field-officer activity by week: visits made, how many were verified (VV-005 score "
        ">= 70), how many the farmer confirmed, and time spent on farms."
    ),
    columns=(
        ("officer_id", "uuid of the field officer"),
        ("officer_name", "the officer's name"),
        ("cluster_id", "uuid of the officer's cluster (null when unassigned)"),
        ("store_id", "uuid of the officer's store (null when unassigned)"),
        ("week_start", "date, the Monday of the ISO week in IST"),
        ("iso_year", "integer ISO year"),
        ("iso_week", "integer ISO week number 1-53"),
        ("visits", "integer, visits checked in that week"),
        ("verified_visits", "integer, visits with status 'verified'"),
        ("partial_visits", "integer, visits with status 'partial'"),
        ("confirmed_visits", "integer, visits the farmer confirmed"),
        ("farmers_visited", "integer, distinct farmers visited"),
        ("minutes_on_farm", "integer, total checked-in minutes"),
    ),
    sql=f"""
SELECT
    v.tenant_id,
    v.officer_id,
    u.name                                            AS officer_name,
    u.cluster_id,
    u.store_id,
    (date_trunc('week', v.checkin_at AT TIME ZONE 'Asia/Kolkata'))::date AS week_start,
    EXTRACT(isoyear FROM v.checkin_at AT TIME ZONE 'Asia/Kolkata')::int  AS iso_year,
    EXTRACT(week    FROM v.checkin_at AT TIME ZONE 'Asia/Kolkata')::int  AS iso_week,
    count(*)::int                                                        AS visits,
    count(*) FILTER (WHERE v.status = 'verified')::int                   AS verified_visits,
    count(*) FILTER (WHERE v.status = 'partial')::int                    AS partial_visits,
    count(*) FILTER (WHERE c.confirmed IS TRUE)::int                     AS confirmed_visits,
    count(DISTINCT v.farmer_id)::int                                     AS farmers_visited,
    (coalesce(sum(v.duration_s), 0) / 60)::int                           AS minutes_on_farm
FROM visit v
JOIN "user" u ON u.id = v.officer_id AND u.tenant_id = v.tenant_id
LEFT JOIN LATERAL (
    SELECT bool_or(vc.status = 'confirmed') AS confirmed
    FROM visit_confirmation vc
    WHERE vc.visit_id = v.id AND vc.deleted_at IS NULL
) c ON true
WHERE v.deleted_at IS NULL
  AND v.{_TENANT}
  AND {SCOPE_FUNCTION}(u.cluster_id, u.store_id)
GROUP BY v.tenant_id, v.officer_id, u.name, u.cluster_id, u.store_id, 6, 7, 8
""".strip(),  # nosec B608 - DDL from module constants; no caller input
)

# --------------------------------------------------------------------------- v_store_day
_STORE_DAY = View(
    name="v_store_day",
    grain="one row per store per IST day",
    description=(
        "Store sales by day: fulfilled orders only (handed over or delivered), money in "
        "integer paise."
    ),
    columns=(
        ("store_id", "uuid of the store"),
        ("store_code", "short store code, e.g. WGL"),
        ("store_name", "store name"),
        ("cluster_id", "uuid of the store's cluster"),
        ("district", "district of the store"),
        ("date_day", "date, the IST day the order was placed"),
        ("orders", "integer, fulfilled orders that day"),
        ("gross_paise", "bigint, sum of subtotals in paise"),
        ("discount_paise", "bigint, sum of discounts in paise"),
        ("net_paise", "bigint, gross minus discount, in paise"),
        ("farmers_served", "integer, distinct farmers who bought"),
    ),
    sql=f"""
SELECT
    o.tenant_id,
    o.store_id,
    s.code                                                            AS store_code,
    s.name                                                            AS store_name,
    s.cluster_id,
    s.district,
    (coalesce(o.placed_at, o.created_at) AT TIME ZONE 'Asia/Kolkata')::date AS date_day,
    count(*)::int                                                     AS orders,
    coalesce(sum(o.subtotal_paise), 0)::bigint                        AS gross_paise,
    coalesce(sum(o.discount_paise), 0)::bigint                        AS discount_paise,
    coalesce(sum(o.subtotal_paise - o.discount_paise), 0)::bigint     AS net_paise,
    count(DISTINCT o.farmer_id)::int                                  AS farmers_served
FROM "order" o
JOIN store s ON s.id = o.store_id AND s.tenant_id = o.tenant_id
WHERE o.deleted_at IS NULL
  AND o.status IN ('handed_over', 'delivered')
  AND o.{_TENANT}
  AND {SCOPE_FUNCTION}(s.cluster_id, o.store_id)
GROUP BY o.tenant_id, o.store_id, s.code, s.name, s.cluster_id, s.district, 7
""".strip(),  # nosec B608 - DDL from module constants; no caller input
)

# --------------------------------------------------------------------------- v_farmer_summary
_FARMER_SUMMARY = View(
    name="v_farmer_summary",
    grain="one row per farmer",
    description=(
        "Farmers with their district, acreage and activity. No farmer name, phone, address "
        "or location is available anywhere (AN-014) — farmers are identified by farmer_id."
    ),
    columns=(
        ("farmer_id", "uuid of the farmer"),
        ("cluster_id", "uuid of the cluster of the farmer's village store"),
        ("store_id", "uuid of the farmer's village store"),
        ("district", "district of the farmer's village"),
        ("mandal", "mandal (block) of the farmer's village"),
        ("registered_on", "date the farmer was registered (IST)"),
        ("source", "how they were registered: officer, app or import"),
        ("acres", "numeric, total farm area in acres"),
        ("farms", "integer, number of farms"),
        ("crop_plots", "integer, number of crop plots"),
        ("last_visit_date", "date of the last visit, null if never visited"),
        ("last_order_date", "date of the last fulfilled order, null if never bought"),
        ("orders", "integer, fulfilled orders"),
        ("net_paise", "bigint, lifetime net spend in paise"),
    ),
    sql=f"""
SELECT
    f.tenant_id,
    f.id                                                        AS farmer_id,
    st.cluster_id,
    vg.store_id,
    vg.district,
    vg.mandal,
    (f.created_at AT TIME ZONE 'Asia/Kolkata')::date            AS registered_on,
    f.source,
    coalesce(fa.acres, 0)::numeric                              AS acres,
    coalesce(fa.farms, 0)::int                                  AS farms,
    coalesce(fa.crop_plots, 0)::int                             AS crop_plots,
    vi.last_visit_date,
    od.last_order_date,
    coalesce(od.orders, 0)::int                                 AS orders,
    coalesce(od.net_paise, 0)::bigint                           AS net_paise
FROM farmer f
JOIN village vg ON vg.id = f.village_id AND vg.tenant_id = f.tenant_id
LEFT JOIN store st ON st.id = vg.store_id AND st.tenant_id = f.tenant_id
LEFT JOIN LATERAL (
    SELECT sum(fm.area_acres) AS acres,
           count(*) AS farms,
           (SELECT count(*) FROM crop_plot cp
             JOIN farm f2 ON f2.id = cp.farm_id
            WHERE f2.farmer_id = f.id AND cp.deleted_at IS NULL AND f2.deleted_at IS NULL)
             AS crop_plots
    FROM farm fm WHERE fm.farmer_id = f.id AND fm.deleted_at IS NULL
) fa ON true
LEFT JOIN LATERAL (
    SELECT max((v.checkin_at AT TIME ZONE 'Asia/Kolkata')::date) AS last_visit_date
    FROM visit v WHERE v.farmer_id = f.id AND v.deleted_at IS NULL
) vi ON true
LEFT JOIN LATERAL (
    SELECT max((coalesce(o.placed_at, o.created_at) AT TIME ZONE 'Asia/Kolkata')::date)
             AS last_order_date,
           count(*) AS orders,
           sum(o.subtotal_paise - o.discount_paise) AS net_paise
    FROM "order" o
    WHERE o.farmer_id = f.id AND o.deleted_at IS NULL
      AND o.status IN ('handed_over', 'delivered')
) od ON true
WHERE f.deleted_at IS NULL
  AND f.{_TENANT}
  AND {SCOPE_FUNCTION}(st.cluster_id, vg.store_id)
""".strip(),  # nosec B608 - DDL from module constants; no caller input
)

# --------------------------------------------------------------------------- v_referral_store
_REFERRAL_STORE = View(
    name="v_referral_store",
    grain="one row per store per ISO week (IST)",
    description="FM-013 referrals credited to each store, by the week the referral was created.",
    columns=(
        ("store_id", "uuid of the credited store, null when no store could be resolved"),
        ("store_code", "short store code"),
        ("store_name", "store name"),
        ("cluster_id", "uuid of the store's cluster"),
        ("week_start", "date, the Monday of the ISO week in IST"),
        ("referrals", "integer, referrals created that week"),
        ("attributed", "integer, of those, attributed to a registered farmer"),
        ("rewarded", "integer, of those, already rewarded"),
        ("store_reward_paise", "bigint, reward credited to the store, in paise"),
    ),
    sql=f"""
SELECT
    r.tenant_id,
    r.store_id,
    s.code                                                           AS store_code,
    s.name                                                           AS store_name,
    s.cluster_id,
    (date_trunc('week', r.created_at AT TIME ZONE 'Asia/Kolkata'))::date AS week_start,
    count(*)::int                                                    AS referrals,
    count(*) FILTER (WHERE r.status IN ('attributed', 'rewarded'))::int AS attributed,
    count(*) FILTER (WHERE r.status = 'rewarded')::int               AS rewarded,
    coalesce(sum(r.store_reward_paise) FILTER (WHERE r.status = 'rewarded'), 0)::bigint
                                                                     AS store_reward_paise
FROM referral r
LEFT JOIN store s ON s.id = r.store_id AND s.tenant_id = r.tenant_id
WHERE r.deleted_at IS NULL
  AND r.{_TENANT}
  AND {SCOPE_FUNCTION}(s.cluster_id, r.store_id)
GROUP BY r.tenant_id, r.store_id, s.code, s.name, s.cluster_id, 6
""".strip(),  # nosec B608 - DDL from module constants; no caller input
)

# --------------------------------------------------------------------------- v_mandi_price
_MANDI_PRICE = View(
    name="v_mandi_price_latest",
    grain="one row per crop, market, variety and grade, for the latest date held",
    description=(
        "FM-012 mandi prices from the public source, latest published date only. Prices are "
        "integer paise per quintal and are indicative."
    ),
    columns=(
        ("crop_id", "uuid of the crop"),
        ("crop_code", "crop code, e.g. paddy, cotton"),
        ("crop_name", "English crop name"),
        ("market", "mandi name as published"),
        ("district", "district of the mandi"),
        ("variety", "variety as published, '' when not broken down"),
        ("grade", "grade as published, '' when not broken down"),
        ("price_date", "date the figure was published (IST)"),
        ("min_price_paise", "bigint, minimum price per quintal in paise"),
        ("modal_price_paise", "bigint, modal (headline) price per quintal in paise"),
        ("max_price_paise", "bigint, maximum price per quintal in paise"),
        ("source_name", "display name of the public source"),
    ),
    sql=f"""
SELECT
    m.tenant_id,
    m.crop_id,
    c.code                          AS crop_code,
    c.name                          AS crop_name,
    m.market,
    m.district,
    m.variety,
    m.grade,
    m.price_date,
    m.min_price_paise::bigint       AS min_price_paise,
    m.modal_price_paise::bigint     AS modal_price_paise,
    m.max_price_paise::bigint       AS max_price_paise,
    m.source_name
FROM mandi_price m
JOIN crop c ON c.id = m.crop_id AND c.tenant_id = m.tenant_id
WHERE m.deleted_at IS NULL
  AND m.{_TENANT}
  AND m.price_date = (
      SELECT max(m2.price_date) FROM mandi_price m2
      WHERE m2.tenant_id = m.tenant_id AND m2.crop_id = m.crop_id AND m2.deleted_at IS NULL
  )
""".strip(),  # nosec B608 - DDL from module constants; no caller input
    scoped=False,
)


VIEWS: tuple[View, ...] = (
    _OFFICER_WEEK,
    _STORE_DAY,
    _FARMER_SUMMARY,
    _REFERRAL_STORE,
    _MANDI_PRICE,
)

#: The only relations AN-016 SQL may name.
VIEW_NAMES: frozenset[str] = frozenset(v.name for v in VIEWS)

BY_NAME: dict[str, View] = {v.name: v for v in VIEWS}


# --------------------------------------------------------------------------- prompt schema
def schema_text(names: tuple[str, ...] | None = None) -> str:
    """The view catalogue as the model sees it: names, grains and columns. No data."""
    chosen = [v for v in VIEWS if names is None or v.name in names]
    blocks: list[str] = []
    for view in chosen:
        lines = [f"{view.name} — {view.description}", f"  grain: {view.grain}"]
        lines.append("  tenant_id uuid — always filtered for you; do not select it")
        lines.extend(f"  {column} — {meaning}" for column, meaning in view.columns)
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks)


# --------------------------------------------------------------------------- DDL
def scope_function_statements() -> list[str]:
    """``app_nlq_scope_ok(cluster_id, store_id)``: the caller's scope, read from two GUCs.

    Unset or empty means tenant-wide (owner, director). A cluster head's request sets
    :data:`CLUSTER_SETTING`, so every scoped view returns only that cluster — regardless of
    what the generated SQL says.
    """
    return [
        f"""
CREATE OR REPLACE FUNCTION public.{SCOPE_FUNCTION}(p_cluster uuid, p_store uuid)
RETURNS boolean
LANGUAGE sql STABLE PARALLEL SAFE
SET search_path = pg_catalog, public
AS $$
    SELECT (NULLIF(current_setting('{CLUSTER_SETTING}', true), '') IS NULL
            OR p_cluster = NULLIF(current_setting('{CLUSTER_SETTING}', true), '')::uuid)
       AND (NULLIF(current_setting('{STORE_SETTING}', true), '') IS NULL
            OR p_store = NULLIF(current_setting('{STORE_SETTING}', true), '')::uuid)
$$
""".strip(),  # nosec B608 - DDL from module constants; no caller input
        f"REVOKE ALL ON FUNCTION public.{SCOPE_FUNCTION}(uuid, uuid) FROM PUBLIC",
        f"GRANT EXECUTE ON FUNCTION public.{SCOPE_FUNCTION}(uuid, uuid) TO "
        f"{APP_ROLE}, {MIGRATE_ROLE}, {READONLY_ROLE}",
    ]


def role_statements() -> list[str]:
    """Create ``farmerapp_readonly`` and let the app role ``SET ROLE`` to it.

    The role gets **no** table privileges: :func:`ddl_statements` grants it SELECT on the
    views and nothing else, and ``ALTER DEFAULT PRIVILEGES`` never mentions it, so a table
    created later is not reachable either.
    """
    return [
        f"""
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{READONLY_ROLE}') THEN
        CREATE ROLE {READONLY_ROLE} NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    END IF;
    EXECUTE format('GRANT {READONLY_ROLE} TO %I WITH SET TRUE, INHERIT FALSE', '{APP_ROLE}');
    IF NOT pg_has_role(current_user, '{READONLY_ROLE}', 'SET') THEN
        EXECUTE format('GRANT {READONLY_ROLE} TO %I WITH SET TRUE, INHERIT FALSE', current_user);
    END IF;
END $$
""".strip(),  # nosec B608 - DDL from module constants; no caller input
        f"GRANT USAGE ON SCHEMA public TO {READONLY_ROLE}",
        f"""
DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO {READONLY_ROLE}', current_database());
END $$
""".strip(),  # nosec B608 - DDL from module constants; no caller input
        f"GRANT EXECUTE ON FUNCTION public.{TENANT_FUNCTION}() TO {READONLY_ROLE}",
    ]


def ddl_statements() -> list[str]:
    """Create (or replace) every authorised view and grant SELECT on it — nothing else."""
    out: list[str] = []
    for view in VIEWS:
        out.append(f"DROP VIEW IF EXISTS public.{view.name}")
        out.append(f"CREATE VIEW public.{view.name} AS\n{view.sql}")
        out.append(f"REVOKE ALL ON public.{view.name} FROM PUBLIC")
        out.append(f"GRANT SELECT ON public.{view.name} TO {APP_ROLE}, {READONLY_ROLE}")
    return out


def drop_statements() -> list[str]:
    return [f"DROP VIEW IF EXISTS public.{view.name}" for view in VIEWS]


__all__ = [
    "BY_NAME",
    "CLUSTER_SETTING",
    "READONLY_ROLE",
    "SCOPE_FUNCTION",
    "STORE_SETTING",
    "VIEWS",
    "VIEW_NAMES",
    "View",
    "ddl_statements",
    "drop_statements",
    "role_statements",
    "schema_text",
    "scope_function_statements",
]
