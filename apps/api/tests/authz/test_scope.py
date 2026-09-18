"""SPEC 2.6 permissions matrix as reusable SQLAlchemy filters (``farmerapp.auth.scope``)."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select

from farmerapp.auth.models import User, UserRole
from farmerapp.auth.scope import (
    DEFAULT_VISIBILITY,
    USER_SCOPE,
    ScopeColumns,
    Visibility,
    scope_filters,
    user_scope,
)

TENANT = uuid.UUID(int=1)
CLUSTER = uuid.UUID(int=2)
STORE = uuid.UUID(int=3)


def _actor(role: UserRole, **kw: object) -> User:
    return User(id=uuid.UUID(int=9), tenant_id=TENANT, role=role, **kw)


def _sql(actor: User, cols: ScopeColumns = USER_SCOPE) -> str:
    stmt = select(User.id).where(*scope_filters(actor, cols))
    return str(stmt.compile(compile_kwargs={"literal_binds": True}))


def test_every_role_has_a_visibility() -> None:
    assert set(DEFAULT_VISIBILITY) == set(UserRole)


@pytest.mark.parametrize(
    "role", [UserRole.OWNER, UserRole.DIRECTOR, UserRole.AUDITOR, UserRole.TENANT_ADMIN]
)
def test_tenant_wide_roles_are_only_bound_to_the_tenant(role: UserRole) -> None:
    sql = _sql(_actor(role))
    assert "tenant_id" in sql and "cluster_id" not in sql and "store_id" not in sql
    assert "false" not in sql.lower()


def test_cluster_head_sees_own_cluster_only() -> None:
    sql = _sql(_actor(UserRole.CLUSTER_HEAD, cluster_id=CLUSTER))
    assert "cluster_id" in sql and CLUSTER.hex in sql and "tenant_id" in sql


def test_cluster_head_without_cluster_sees_nothing() -> None:
    assert "false" in _sql(_actor(UserRole.CLUSTER_HEAD, cluster_id=None)).lower()


def test_store_manager_sees_own_store_only() -> None:
    sql = _sql(_actor(UserRole.STORE_MANAGER, store_id=STORE))
    assert "store_id" in sql and STORE.hex in sql
    assert "false" in _sql(_actor(UserRole.STORE_MANAGER, store_id=None)).lower()


@pytest.mark.parametrize("role", [UserRole.FIELD_OFFICER, UserRole.FARMER])
def test_own_records_only(role: UserRole) -> None:
    sql = _sql(_actor(role))
    assert uuid.UUID(int=9).hex in sql and "cluster_id" not in sql


def test_agronomist_has_no_default_access_to_staff_records() -> None:
    assert "false" in _sql(_actor(UserRole.AGRONOMIST)).lower()


def test_visibility_map_can_be_overridden_per_entity() -> None:
    """E.g. farmer profiles: agronomists read crop data (SPEC 2.6), so a caller widens them."""
    actor = _actor(UserRole.AGRONOMIST)
    widened = {**DEFAULT_VISIBILITY, UserRole.AGRONOMIST: Visibility.ALL}
    stmt = select(User.id).where(*scope_filters(actor, USER_SCOPE, visibility=widened))
    sql = str(stmt.compile(compile_kwargs={"literal_binds": True}))
    assert "false" not in sql.lower() and "tenant_id" in sql


def test_entity_without_a_column_falls_closed() -> None:
    """A scope that has no cluster column cannot satisfy 'own cluster': nothing is visible."""
    cols = ScopeColumns(tenant_id=User.tenant_id)
    assert "false" in _sql(_actor(UserRole.CLUSTER_HEAD, cluster_id=CLUSTER), cols).lower()
    assert "false" in _sql(_actor(UserRole.FIELD_OFFICER), cols).lower()


def test_user_scope_shortcut_matches_scope_filters() -> None:
    actor = _actor(UserRole.CLUSTER_HEAD, cluster_id=CLUSTER)
    a = select(User.id).where(*user_scope(actor))
    b = select(User.id).where(*scope_filters(actor, USER_SCOPE))
    assert str(a) == str(b)
