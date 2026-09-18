"""Record-level scope from the SPEC 2.6 permissions matrix, as SQLAlchemy filters.

Role policies (``policy.py``) decide *whether* a role may call a route; scope decides *which
rows* the caller sees once inside. The same helper serves users now and farmers, visits and
khata later: describe the entity's columns with ``ScopeColumns`` and call ``scope_filters``.

Default visibility of staff-scoped records (users, farmers, visits, khata):

    owner / director / tenant_admin / auditor  -> whole tenant
    cluster_head                               -> own cluster
    store_manager                              -> own store
    field_officer / farmer                     -> own records
    agronomist                                 -> nothing (widen per entity: crop data is readable)
    accountant                                 -> whole tenant (finance; 2.6 has no column,
                                                  assumption recorded in docs/prs/FA-002.md)

A role whose scope column is missing on the entity, or whose own cluster/store is not set,
sees nothing (fail closed). Tenant isolation is always the first filter; RLS (FA-003) is the
second line of defence.
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from sqlalchemy import ColumnElement, SQLColumnExpression, false, select

from farmerapp.auth.models import User, UserRole
from farmerapp.farmers.models import Farmer
from farmerapp.location.models import DutySession
from farmerapp.tenants.models import Store, Village
from farmerapp.visits.models import Visit


class Visibility(StrEnum):
    ALL = "all"
    CLUSTER = "cluster"
    STORE = "store"
    OWN = "own"
    NONE = "none"


DEFAULT_VISIBILITY: Mapping[UserRole, Visibility] = {
    UserRole.OWNER: Visibility.ALL,
    UserRole.DIRECTOR: Visibility.ALL,
    UserRole.TENANT_ADMIN: Visibility.ALL,
    UserRole.AUDITOR: Visibility.ALL,
    UserRole.ACCOUNTANT: Visibility.ALL,
    UserRole.CLUSTER_HEAD: Visibility.CLUSTER,
    UserRole.STORE_MANAGER: Visibility.STORE,
    UserRole.FIELD_OFFICER: Visibility.OWN,
    UserRole.AGRONOMIST: Visibility.NONE,
    UserRole.FARMER: Visibility.OWN,
}


@dataclass(frozen=True)
class ScopeColumns:
    """Which columns of an entity carry its tenant, cluster, store and owning user."""

    tenant_id: SQLColumnExpression[Any]
    cluster_id: SQLColumnExpression[Any] | None = None
    store_id: SQLColumnExpression[Any] | None = None
    owner_id: SQLColumnExpression[Any] | None = None


def _eq_or_closed(
    column: SQLColumnExpression[Any] | None, value: uuid.UUID | None
) -> ColumnElement[bool]:
    if column is None or value is None:
        return false()
    return column == value


def scope_filters(
    actor: User,
    cols: ScopeColumns,
    visibility: Mapping[UserRole, Visibility] = DEFAULT_VISIBILITY,
) -> list[ColumnElement[bool]]:
    """Filters to AND into a query so ``actor`` only sees rows the 2.6 matrix allows."""
    filters: list[ColumnElement[bool]] = [cols.tenant_id == actor.tenant_id]
    match visibility[UserRole(actor.role)]:
        case Visibility.ALL:
            pass
        case Visibility.CLUSTER:
            filters.append(_eq_or_closed(cols.cluster_id, actor.cluster_id))
        case Visibility.STORE:
            filters.append(_eq_or_closed(cols.store_id, actor.store_id))
        case Visibility.OWN:
            filters.append(_eq_or_closed(cols.owner_id, actor.id))
        case Visibility.NONE:
            filters.append(false())
    return filters


USER_SCOPE = ScopeColumns(
    tenant_id=User.tenant_id, cluster_id=User.cluster_id, store_id=User.store_id, owner_id=User.id
)


def user_scope(actor: User) -> list[ColumnElement[bool]]:
    """Which ``user`` rows ``actor`` may see."""
    return scope_filters(actor, USER_SCOPE)


# --------------------------------------------------------------------------- farmers
#: SPEC 2.6 "Farmer profile" row: the agronomist reads crop data (the router redacts PII).
FARMER_VISIBILITY: Mapping[UserRole, Visibility] = {
    **DEFAULT_VISIBILITY,
    UserRole.AGRONOMIST: Visibility.ALL,
}


def farmer_filters(
    actor: User, visibility: Mapping[UserRole, Visibility] = FARMER_VISIBILITY
) -> list[ColumnElement[bool]]:
    """Which ``farmer`` rows ``actor`` may see (SPEC 2.6, "Farmer profile").

    A farmer belongs to a store through its village (``village.store_id``) and to a cluster
    through that store (``store.cluster_id``); a field officer owns the farmers they
    registered (``farmer.registered_by``); a farmer is their own record (``farmer.user_id``).
    """
    filters: list[ColumnElement[bool]] = [Farmer.tenant_id == actor.tenant_id]
    role = UserRole(actor.role)
    match visibility[role]:
        case Visibility.ALL:
            pass
        case Visibility.CLUSTER:
            if actor.cluster_id is None:
                filters.append(false())
            else:
                villages = (
                    select(Village.id)
                    .join(Store, Store.id == Village.store_id)
                    .where(
                        Village.tenant_id == actor.tenant_id, Store.cluster_id == actor.cluster_id
                    )
                )
                filters.append(Farmer.village_id.in_(villages))
        case Visibility.STORE:
            if actor.store_id is None:
                filters.append(false())
            else:
                villages = select(Village.id).where(
                    Village.tenant_id == actor.tenant_id, Village.store_id == actor.store_id
                )
                filters.append(Farmer.village_id.in_(villages))
        case Visibility.OWN:
            owner = Farmer.user_id if role == UserRole.FARMER else Farmer.registered_by
            filters.append(_eq_or_closed(owner, actor.id))
        case Visibility.NONE:
            filters.append(false())
    return filters


# --------------------------------------------------------------------------- officers
#: SPEC 2.6 "Officer location track": owner / director / auditor read, cluster head own
#: cluster, field officer own; **never** store managers or other officers. Duty sessions
#: follow the same row.
TRACK_VISIBILITY: Mapping[UserRole, Visibility] = {
    **DEFAULT_VISIBILITY,
    UserRole.ACCOUNTANT: Visibility.NONE,
    UserRole.STORE_MANAGER: Visibility.NONE,
    UserRole.AGRONOMIST: Visibility.NONE,
    UserRole.FARMER: Visibility.NONE,
}


def officer_filters(
    actor: User, visibility: Mapping[UserRole, Visibility] = TRACK_VISIBILITY
) -> list[ColumnElement[bool]]:
    """Which ``user`` rows (officers) ``actor`` may see the duty / track data of."""
    return scope_filters(actor, USER_SCOPE, visibility)


def duty_session_filters(actor: User) -> list[ColumnElement[bool]]:
    """Which ``duty_session`` rows ``actor`` may see (SPEC 2.6 "Officer location track")."""
    officers = select(User.id).where(*officer_filters(actor))
    return [DutySession.tenant_id == actor.tenant_id, DutySession.officer_id.in_(officers)]


# --------------------------------------------------------------------------- visits
#: Visits are officer activity about a farmer: the "Farmer profile" row of SPEC 2.6 minus
#: the agronomist (notes are not crop data); a farmer sees visits made to them.
VISIT_VISIBILITY: Mapping[UserRole, Visibility] = {
    **DEFAULT_VISIBILITY,
    UserRole.ACCOUNTANT: Visibility.NONE,
    UserRole.AGRONOMIST: Visibility.NONE,
}


def visit_filters(
    actor: User, visibility: Mapping[UserRole, Visibility] = VISIT_VISIBILITY
) -> list[ColumnElement[bool]]:
    """Which ``visit`` rows ``actor`` may see: by the officer's cluster / store, the
    officer's own visits, or (farmer) visits to the farmer record linked to the login."""
    filters: list[ColumnElement[bool]] = [Visit.tenant_id == actor.tenant_id]
    role = UserRole(actor.role)
    match visibility[role]:
        case Visibility.ALL:
            pass
        case Visibility.CLUSTER:
            if actor.cluster_id is None:
                filters.append(false())
            else:
                officers = select(User.id).where(
                    User.tenant_id == actor.tenant_id, User.cluster_id == actor.cluster_id
                )
                filters.append(Visit.officer_id.in_(officers))
        case Visibility.STORE:
            if actor.store_id is None:
                filters.append(false())
            else:
                officers = select(User.id).where(
                    User.tenant_id == actor.tenant_id, User.store_id == actor.store_id
                )
                filters.append(Visit.officer_id.in_(officers))
        case Visibility.OWN:
            if role == UserRole.FARMER:
                own = select(Farmer.id).where(
                    Farmer.tenant_id == actor.tenant_id, Farmer.user_id == actor.id
                )
                filters.append(Visit.farmer_id.in_(own))
            else:
                filters.append(Visit.officer_id == actor.id)
        case Visibility.NONE:
            filters.append(false())
    return filters


__all__ = [
    "DEFAULT_VISIBILITY",
    "FARMER_VISIBILITY",
    "TRACK_VISIBILITY",
    "USER_SCOPE",
    "VISIT_VISIBILITY",
    "ScopeColumns",
    "Visibility",
    "duty_session_filters",
    "farmer_filters",
    "officer_filters",
    "scope_filters",
    "user_scope",
    "visit_filters",
]
