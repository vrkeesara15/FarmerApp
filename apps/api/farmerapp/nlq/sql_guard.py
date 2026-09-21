"""AN-016: the SQL validator. Nothing reaches the database until this says yes.

``validate(sql)`` parses with **sqlglot** (Postgres dialect) and returns a
:class:`ValidSql` — the statement rewritten with a hard ``LIMIT`` — or raises
:class:`SqlRejectedError` with a reason the caller can show the user.

What is rejected, and why each rule exists:

=============================== ==============================================================
rule                            what it stops
=============================== ==============================================================
one statement only              ``SELECT 1; DROP TABLE farmer`` — stacked queries
must be a ``SELECT``            every DDL and DML statement, ``COPY``, ``CALL``, ``DO``,
                                ``GRANT``, ``SET``, ``VACUUM``, ``EXPLAIN``, ``SHOW``
no write node anywhere          ``WITH x AS (DELETE FROM … RETURNING *) SELECT * FROM x`` —
                                the CTE-based write that a "must start with SELECT" check
                                misses
relations in the allowlist      any table, any other view, ``pg_catalog``, ``information_schema``
no qualified relation names     ``other_schema.v_officer_week``, ``db.schema.table``
functions in the allowlist      ``pg_read_file``, ``dblink``, ``lo_import``, ``query_to_xml``,
                                ``pg_sleep``, ``current_setting``, ``set_config``, ``cast`` to
                                a regclass, and everything else not explicitly needed
no ``INTO``                     ``SELECT … INTO newtable`` (a write in ``SELECT`` clothing)
no locking clause               ``FOR UPDATE`` (takes row locks, and needs write intent)
no placeholders                 ``$1`` / ``?`` — the statement must be complete and readable
a bounded ``LIMIT``             a cartesian product that would run until the timeout
=============================== ==============================================================

The allowlists are **positive**: a construct is refused unless it is named here. New SQL the
model invents therefore fails closed, which is the only safe default for generated code.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import cast

import sqlglot
from sqlglot import exp

from farmerapp.nlq.views import VIEW_NAMES

DIALECT = "postgres"

#: Functions the model may call. Aggregates, dates, numbers, strings, conditionals — enough
#: to answer a business question, and nothing that touches the server, the catalogue or a file.
#:
#: These are **sqlglot's canonical names** (``Expression.sql_name()``), not the Postgres
#: spelling: ``date_trunc`` parses to ``timestamp_trunc``, ``to_char`` to ``time_to_str``,
#: ``string_agg`` to ``group_concat``. ``tests/nlq/test_sql_guard.py`` pins the mapping so a
#: sqlglot upgrade that renames one is a failing test, not a silently rejected question.
ALLOWED_FUNCTIONS: frozenset[str] = frozenset(
    {
        # aggregates
        "avg",
        "count",
        "max",
        "min",
        "sum",
        "stddev",
        "variance",
        "percentile_cont",
        "array_agg",
        "group_concat",  # string_agg
        "bool_or",
        "bool_and",
        # window helpers
        "row_number",
        "rank",
        "dense_rank",
        "lag",
        "lead",
        "ntile",
        # conditionals / null handling
        "coalesce",
        "nullif",
        "greatest",
        "least",
        "case",
        "if",
        # numbers
        "abs",
        "ceil",
        "ceiling",
        "floor",
        "round",
        "trunc",
        "mod",
        "power",
        "sqrt",
        "div",
        # dates (sqlglot canonical names)
        "current_date",
        "current_timestamp",
        "timestamp_trunc",  # date_trunc
        "date_trunc",
        "date_part",
        "extract",
        "make_date",
        "to_date",
        "str_to_date",
        "time_to_str",  # to_char
        "date_add",
        "date_sub",
        "date_diff",
        "datetime_diff",
        "interval",
        # strings
        "concat",
        "lower",
        "upper",
        "trim",
        "ltrim",
        "rtrim",
        "length",
        "substring",
        "left",
        "right",
        "replace",
        "split_part",
        "initcap",
        "position",
        # casts sqlglot models as functions (the target type is checked separately)
        "cast",
        "try_cast",
    }
)

#: Casts to these types only. A cast to ``regclass`` / ``regproc`` resolves catalogue objects.
ALLOWED_CAST_TYPES: frozenset[str] = frozenset(
    {
        "BIGINT",
        "BOOLEAN",
        "DATE",
        "DECIMAL",
        "DOUBLE",
        "FLOAT",
        "INT",
        "INTERVAL",
        "NUMERIC",
        "SMALLINT",
        "TEXT",
        "TIMESTAMP",
        "TIMESTAMPTZ",
        "UUID",
        "VARCHAR",
    }
)

#: Any expression class here means the statement writes, locks or escapes. Fail closed.
_FORBIDDEN_NODES: tuple[type[exp.Expression], ...] = (
    exp.Insert,
    exp.Update,
    exp.Delete,
    exp.Merge,
    exp.Create,
    exp.Drop,
    exp.Alter,
    exp.TruncateTable,
    exp.Grant,
    exp.Copy,
    exp.Command,  # anything sqlglot parses as a raw command: SET, CALL, DO, VACUUM, COPY…
    exp.Transaction,
    exp.Commit,
    exp.Rollback,
    exp.Use,
    exp.Set,
    exp.Lock,
    exp.Into,
    exp.Placeholder,
    exp.Parameter,
    exp.SessionParameter,
)

#: Schema-qualified access is never needed: the five views live in ``public`` and are resolved
#: by ``search_path``. Naming any schema at all is refused (``pg_catalog`` included).
_BLOCKED_PREFIXES = ("pg_", "information_schema")


class SqlRejectedError(ValueError):
    """The generated SQL may not run. ``reason`` is shown to the caller."""

    def __init__(self, reason: str) -> None:
        self.reason = reason
        super().__init__(reason)


@dataclass(frozen=True)
class ValidSql:
    """Validated SQL, ready to run."""

    #: The statement as generated (what the caller is shown as "SQL used").
    sql: str
    #: The statement actually executed: the same query with the row cap applied.
    executable: str
    #: The authorised views it reads.
    relations: tuple[str, ...]


def _name(node: exp.Expression | str | None) -> str:
    if node is None:
        return ""
    if isinstance(node, str):
        return node
    return str(node.name or "")


def _cte_names(tree: exp.Expression) -> frozenset[str]:
    """Names introduced by ``WITH``. Their bodies are validated like any other SELECT."""
    return frozenset(_name(cte.args.get("alias")).lower() for cte in tree.find_all(exp.CTE))


def _check_relations(tree: exp.Expression) -> tuple[str, ...]:
    local = _cte_names(tree)
    seen: list[str] = []
    for table in tree.find_all(exp.Table):
        catalog = _name(table.args.get("catalog")).lower()
        schema = _name(table.args.get("db")).lower()
        if catalog or (schema and schema != "public"):
            raise SqlRejectedError(
                f"the query names a schema ({table.sql(dialect=DIALECT)}); only the "
                "authorised views may be read"
            )
        name = _name(table.this).lower()
        if any(name.startswith(prefix) for prefix in _BLOCKED_PREFIXES):
            raise SqlRejectedError(f"'{name}' is a system catalogue and may not be read")
        if name in local:  # a WITH name; its own body was checked as part of this walk
            continue
        if name not in VIEW_NAMES:
            raise SqlRejectedError(
                f"'{name}' is not an authorised view (allowed: {', '.join(sorted(VIEW_NAMES))})"
            )
        if name not in seen:
            seen.append(name)
    if not seen:
        raise SqlRejectedError("the query does not read any authorised view")
    return tuple(seen)


def _check_functions(tree: exp.Expression) -> None:
    for node in tree.find_all(exp.Func):
        # AND / OR / NOT are modelled as functions by sqlglot; they are plain boolean logic.
        if isinstance(node, exp.Connector | exp.Not):
            continue
        if isinstance(node, exp.Anonymous):
            name = _name(node.this).lower() or str(node.args.get("this", "")).lower()
            raise SqlRejectedError(f"the function '{name}' is not allowed")
        key = node.sql_name().lower()
        if key not in ALLOWED_FUNCTIONS:
            raise SqlRejectedError(f"the function '{key}' is not allowed")
    for node in tree.find_all(exp.Cast):
        target = str(node.to.this).split(".")[-1].upper()
        if target not in ALLOWED_CAST_TYPES:
            raise SqlRejectedError(f"casting to {target.lower()} is not allowed")


def _check_shape(tree: exp.Expression) -> None:
    for node in tree.walk():
        if isinstance(node, _FORBIDDEN_NODES):
            raise SqlRejectedError("only a single read-only SELECT is allowed")
    if tree.args.get("locks"):
        raise SqlRejectedError("locking clauses (FOR UPDATE / FOR SHARE) are not allowed")


def _apply_limit(tree: exp.Expression, row_limit: int) -> exp.Expression:
    """Cap the result, keeping a smaller limit the model chose itself."""
    limited = cast(exp.Query, tree.copy())
    existing = limited.args.get("limit")
    if existing is not None:
        try:
            asked = int(_name(existing.expression) or existing.expression.this)
        except (AttributeError, TypeError, ValueError):
            asked = row_limit
        if asked <= row_limit:
            return cast(exp.Expression, limited)
    return cast(exp.Expression, limited.limit(row_limit))


def validate(sql: str, *, row_limit: int = 200) -> ValidSql:
    """Parse and check ``sql``; raise :class:`SqlRejectedError` with a readable reason."""
    text = (sql or "").strip().rstrip(";").strip()
    if not text:
        raise SqlRejectedError("no SQL was produced")
    try:
        statements = sqlglot.parse(text, dialect=DIALECT)
    except sqlglot.ParseError as exc:
        raise SqlRejectedError(f"the SQL could not be parsed: {str(exc).splitlines()[0]}") from exc
    statements = [s for s in statements if s is not None]
    if len(statements) != 1:
        raise SqlRejectedError("exactly one statement is allowed")
    tree = statements[0]
    if not isinstance(tree, exp.Select | exp.SetOperation | exp.Subquery):
        raise SqlRejectedError("only a single read-only SELECT is allowed")
    _check_shape(tree)
    relations = _check_relations(tree)
    _check_functions(tree)
    executable = _apply_limit(tree, row_limit)
    return ValidSql(
        sql=tree.sql(dialect=DIALECT, pretty=True),
        executable=executable.sql(dialect=DIALECT),
        relations=relations,
    )


__all__ = [
    "ALLOWED_CAST_TYPES",
    "ALLOWED_FUNCTIONS",
    "DIALECT",
    "SqlRejectedError",
    "ValidSql",
    "validate",
]
