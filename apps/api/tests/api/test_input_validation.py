"""SEC-022, API half: "input validation with Pydantic models".

A meta-test over every route the app actually serves, in the spirit of the SEC-006 authz
matrix: rather than trusting that each new endpoint remembered to constrain its input, walk
the FastAPI dependency tree and assert the three properties that make the rule real.

1. **Every request body is a Pydantic model.** A ``dict``/``Any`` body is an unvalidated
   hole; ``Model | None`` (an optional body) is fine.
2. **Every free-text field is bounded.** A plain ``str`` field must carry ``max_length`` or
   a ``pattern`` — in the field, in an ``Annotated[str, StringConstraints(...)]`` alias, or
   anywhere inside a union. An unbounded string is a storage bug and a cheap DoS. A field
   whose constraint lives in a ``field_validator`` instead (phone numbers are *parsed*, not
   pattern-matched) cannot be detected by reading the model, so it goes in the allow-list
   below with the validator named.
3. **Every ``str`` query parameter is bounded** for the same reason: query strings reach the
   database through filters.

``ALLOWED_UNBOUNDED`` is the escape hatch and it is meant to stay short: each entry names a
field and why it has no length, and the test fails if an entry becomes stale, so a fix
removes the entry rather than leaving it behind.
"""

from __future__ import annotations

import types
import typing
from collections.abc import Iterator
from typing import Annotated, Any

import pytest
from pydantic import BaseModel

from farmerapp.api.app import create_app
from farmerapp.auth.policy import iter_api_routes

#: field path -> why it is not length-bounded. Keep this list short and dated.
ALLOWED_UNBOUNDED: dict[str, str] = {
    # Parsed, not matched: a field validator normalises the number and rejects anything that
    # is not a 10-digit Indian mobile (`must be an Indian mobile number`).
    "farmerapp.auth.schemas.OtpSendRequest.phone": "validated by _phone (FA-001)",
    "farmerapp.auth.schemas.OtpVerifyRequest.phone": "validated by _phone (FA-001)",
    "farmerapp.farmers.schemas.FarmerCreate.phone": "validated by _phone (FA-012)",
    "farmerapp.farmers.schemas.PhoneVerifySendRequest.phone": "validated by _phone",
    "farmerapp.farmers.schemas.PhoneVerifyConfirmRequest.phone": "validated by _phone",
    "farmerapp.users.schemas.UserCreate.phone": "validated by _phone (WC-011)",
}

#: query parameter -> why it is not length-bounded.
ALLOWED_UNBOUNDED_QUERY: dict[str, str] = {
    # Owned by the analytics workstream (apps/api/analytics); reported in
    # docs/prs/M7-security-privacy.md so the owner bounds them.
    "GET /v1/analytics/farmers?sort": "analytics workstream: bound with a Literal (M7 follow-up)",
    "GET /v1/analytics/farmers?cursor": "analytics workstream: bound to the cursor length",
}

_UNION = (typing.Union, types.UnionType)


def _leaves(annotation: Any) -> Iterator[Any]:
    """Every non-container type inside an annotation (unions and Annotated unwrapped)."""
    if hasattr(annotation, "__metadata__"):
        yield from _leaves(typing.get_args(annotation)[0])
        return
    origin = typing.get_origin(annotation)
    if origin in _UNION:
        for arg in typing.get_args(annotation):
            if arg is not type(None):
                yield from _leaves(arg)
        return
    yield annotation


def _is_plain_str(annotation: Any) -> bool:
    """True for ``str`` / ``str | None`` / an ``Annotated[str, ...]`` alias — not a container."""
    leaves = list(_leaves(annotation))
    return bool(leaves) and all(leaf is str for leaf in leaves)


def _has_constraint(node: Any) -> bool:
    """A ``max_length`` / ``pattern`` anywhere in a field's metadata or its annotation."""
    if node is None:
        return False
    if getattr(node, "max_length", None) or getattr(node, "pattern", None):
        return True
    for meta in getattr(node, "metadata", ()) or ():
        if _has_constraint(meta):
            return True
    if hasattr(node, "__metadata__"):
        if any(_has_constraint(m) for m in node.__metadata__):
            return True
        return _has_constraint(typing.get_args(node)[0])
    if typing.get_origin(node) in _UNION:
        return any(_has_constraint(a) for a in typing.get_args(node) if a is not type(None))
    return False


def _constrained(field: Any) -> bool:
    return _has_constraint(field) or _has_constraint(field.annotation)


def _models() -> dict[type[BaseModel], None]:
    """Every Pydantic model reachable from a request body, in a stable order."""
    app = create_app()
    seen: dict[type[BaseModel], None] = {}

    def walk(annotation: Any) -> None:
        for arg in typing.get_args(annotation):
            if arg is not type(None):
                walk(arg)
        if isinstance(annotation, type) and issubclass(annotation, BaseModel):
            if annotation in seen:
                return
            seen[annotation] = None
            for f in annotation.model_fields.values():
                walk(f.annotation)

    for _path, route in iter_api_routes(app):
        for param in route.dependant.body_params:
            walk(param.field_info.annotation)
    return seen


def _string_fields() -> list[tuple[str, Any]]:
    out: list[tuple[str, Any]] = []
    for model in _models():
        for name, field in model.model_fields.items():
            if _is_plain_str(field.annotation):
                out.append((f"{model.__module__}.{model.__name__}.{name}", field))
    return sorted(out, key=lambda pair: pair[0])


STRING_FIELDS = _string_fields()


# --------------------------------------------------------------------------- bodies
def test_every_request_body_is_a_pydantic_model() -> None:
    app = create_app()
    offenders: list[str] = []
    for path, route in iter_api_routes(app):
        for param in route.dependant.body_params:
            if not all(
                isinstance(leaf, type) and issubclass(leaf, BaseModel)
                for leaf in _leaves(param.field_info.annotation)
            ):
                methods = ",".join(sorted(route.methods or ()))
                offenders.append(f"{methods} {path}: {param.name} is {param.field_info.annotation}")
    assert offenders == [], offenders


def test_the_app_has_request_bodies_to_check() -> None:
    """Guards the meta-test itself: an empty walk would pass everything silently."""
    assert len(STRING_FIELDS) > 50
    assert len(_models()) > 100


@pytest.mark.parametrize(("path", "field"), STRING_FIELDS, ids=[p for p, _ in STRING_FIELDS])
def test_every_free_text_field_is_bounded(path: str, field: Any) -> None:
    if path in ALLOWED_UNBOUNDED:
        pytest.skip(f"documented: {ALLOWED_UNBOUNDED[path]}")
    assert _constrained(field), (
        f"{path} accepts an unbounded string (SEC-022). Add max_length / a pattern, or a "
        f"documented entry in ALLOWED_UNBOUNDED."
    )


def test_the_unbounded_allowlist_has_no_stale_entries() -> None:
    """A fix must delete its allowlist entry, not leave it behind."""
    known = {path for path, _ in STRING_FIELDS}
    stale = sorted(set(ALLOWED_UNBOUNDED) - known)
    assert stale == [], f"remove from ALLOWED_UNBOUNDED: {stale}"
    still_unbounded = {path for path, field in STRING_FIELDS if not _constrained(field)}
    fixed = sorted(set(ALLOWED_UNBOUNDED) - still_unbounded)
    assert fixed == [], f"now bounded, remove from ALLOWED_UNBOUNDED: {fixed}"


# --------------------------------------------------------------------------- query strings
def _query_strings() -> list[tuple[str, Any]]:
    app = create_app()
    out: list[tuple[str, Any]] = []
    for path, route in iter_api_routes(app):
        methods = ",".join(sorted(route.methods or ()))
        for param in route.dependant.query_params:
            if _is_plain_str(param.field_info.annotation):
                out.append((f"{methods} {path}?{param.name}", param.field_info))
    return sorted(out, key=lambda pair: pair[0])


QUERY_STRINGS = _query_strings()


@pytest.mark.parametrize(
    ("path", "field"), QUERY_STRINGS, ids=[p for p, _ in QUERY_STRINGS] or ["none"]
)
def test_every_string_query_parameter_is_bounded(path: str, field: Any) -> None:
    if path in ALLOWED_UNBOUNDED_QUERY:
        pytest.skip(f"documented: {ALLOWED_UNBOUNDED_QUERY[path]}")
    assert _constrained(field), (
        f"{path} accepts an unbounded string (SEC-022). Add max_length / a pattern, or use a "
        f"Literal / Enum."
    )


def test_the_query_allowlist_has_no_stale_entries() -> None:
    known = {path for path, _ in QUERY_STRINGS}
    stale = sorted(set(ALLOWED_UNBOUNDED_QUERY) - known)
    assert stale == [], f"remove from ALLOWED_UNBOUNDED_QUERY: {stale}"


# --------------------------------------------------------------------------- the new schemas
def test_the_dpdp_schemas_forbid_unknown_fields() -> None:
    """NF-013 input reaches the farmer record; nothing unexpected may ride along."""
    from farmerapp.privacy.router import CorrectionRequestIn, GrievanceIn

    for model in (CorrectionRequestIn, GrievanceIn):
        assert model.model_config.get("extra") == "forbid", model.__name__


def test_annotated_alias_constraints_are_recognised() -> None:
    """Regression guard for the detector: Annotated[str, StringConstraints(...)] counts."""
    from pydantic import StringConstraints

    class _Sample(BaseModel):
        bounded: Annotated[str, StringConstraints(max_length=10)] | None = None
        unbounded: str | None = None

    assert _constrained(_Sample.model_fields["bounded"])
    assert not _constrained(_Sample.model_fields["unbounded"])
