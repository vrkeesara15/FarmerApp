"""SEC-006: authorisation matrix generated from ``apps/api/openapi.yaml``.

Every operation in the contract carries either ``x-public: true`` or ``x-roles: [...]``
(emitted by ``farmerapp.auth.policy``). For each protected operation this module
parametrises over all ten roles and asserts that allowed roles are *not* rejected on
authorisation grounds (any status except 401/403 — business validity is the job of the
feature's own tests) and denied roles get a ``403 forbidden`` problem. It also proves that a
tenant-A token never reaches tenant-B data, that unknown or disabled users get 401, and that
forbidden calls are logged (FA-002).

Adding a route: give it a policy (or the app refuses to start), regenerate ``openapi.yaml``
and, when the route takes path parameters or a body, add a ``RouteFixture`` below.
"""

from __future__ import annotations

import json
import logging
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest
import yaml
from httpx import AsyncClient, Response

from farmerapp.api.errors import PROBLEM_MEDIA_TYPE
from farmerapp.auth.models import User, UserRole, UserStatus
from tests.authz.conftest import ROLES, Bearer, SeededTenant, World

OPENAPI_PATH = Path(__file__).resolve().parents[2] / "openapi.yaml"
METHODS = ("get", "post", "put", "patch", "delete")


@dataclass(frozen=True)
class Operation:
    method: str
    path: str
    public: bool
    roles: frozenset[str]
    self_param: str | None

    @property
    def id(self) -> str:
        return f"{self.method.upper()} {self.path}"

    @property
    def has_path_params(self) -> bool:
        return "{" in self.path


def load_operations() -> list[Operation]:
    spec = yaml.safe_load(OPENAPI_PATH.read_text())
    ops: list[Operation] = []
    for path, item in spec["paths"].items():
        for method in METHODS:
            op = item.get(method)
            if op is None:
                continue
            ops.append(
                Operation(
                    method=method,
                    path=path,
                    public=bool(op.get("x-public", False)),
                    roles=frozenset(op.get("x-roles", ())),
                    self_param=op.get("x-self"),
                )
            )
    return ops


OPERATIONS = load_operations()
PROTECTED = [op for op in OPERATIONS if not op.public]
PUBLIC = [op for op in OPERATIONS if op.public]
WITH_ID = [op for op in PROTECTED if op.has_path_params]


# --------------------------------------------------------------------------- fixtures table
@dataclass(frozen=True)
class Ctx:
    """What a request is made *as* and *about*: the actor and the tenant whose data it targets."""

    actor: User
    target: SeededTenant


@dataclass(frozen=True)
class RouteFixture:
    """Minimal valid request for an operation. Defaults: no path params, no body."""

    path_params: Callable[[Ctx], dict[str, str]] = field(default=lambda _ctx: {})
    body: Callable[[Ctx], dict[str, Any] | None] = field(default=lambda _ctx: None)
    query: dict[str, str] = field(default_factory=dict)
    # Raw body + extra headers (signed webhooks): used instead of ``body`` when set.
    raw: Callable[[Ctx], tuple[bytes, dict[str, str]]] | None = None


def _target_owner_id(ctx: Ctx) -> dict[str, str]:
    return {"id": str(ctx.target.owner.id)}


def _target_farmer_id(ctx: Ctx) -> dict[str, str]:
    return {"id": str(ctx.target.farmer.id)}


def _target_farm_id(ctx: Ctx) -> dict[str, str]:
    return {"id": str(ctx.target.farm_id)}


def _target_plot_id(ctx: Ctx) -> dict[str, str]:
    return {"id": str(ctx.target.crop_plot_id)}


def _target_visit_id(ctx: Ctx) -> dict[str, str]:
    return {"id": str(ctx.target.visit_id)}


def _target_officer_id(ctx: Ctx) -> dict[str, str]:
    # The role officer: for the field_officer row of the matrix this is the actor (own track).
    return {"id": str(ctx.target.user(UserRole.FIELD_OFFICER).id)}


def _random_upload(_ctx: Ctx) -> dict[str, str]:
    # Uploads are private to the actor who started them: any id is a 404 for everyone else.
    return {"upload_id": "00000000-0000-0000-0000-000000000000", "index": "0"}


def _checkin_body(ctx: Ctx) -> dict[str, Any]:
    # A meeting-point-less, farm-less check-in: 404 / 422 for allowed roles, never 401 / 403.
    return {
        "farmer_id": str(ctx.target.farmer.id),
        "purpose": "advisory",
        "checkin_at": "2026-09-18T10:00:00+00:00",
        "checkin_point": {"lat": 18.02, "lon": 79.55, "accuracy_m": 10},
    }


def _farmer_body(ctx: Ctx) -> dict[str, Any]:
    return {
        "phone": "+919000177001",
        "name": "Matrix Farmer",
        "village_id": str(ctx.target.farmer.village_id),
    }


NO_SUCH_ID = "00000000-0000-0000-0000-000000000000"


def _signed_webhook(ctx: Ctx) -> tuple[bytes, dict[str, str]]:
    # SEC-023: a correctly signed, fresh event for an unknown payment -> 200 ignored.
    import time

    from farmerapp.payments.providers import hmac_sha256_hex
    from farmerapp.settings import get_settings

    body = json.dumps(
        {
            "entity": "event",
            "event": "payment.captured",
            "payload": {
                "payment": {
                    "entity": {
                        "id": "pay_matrix",
                        "amount": 100,
                        "notes": {"tenant_id": str(ctx.target.tenant.id), "payment_id": NO_SUCH_ID},
                    }
                }
            },
            "created_at": int(time.time()),
        }
    ).encode()
    signature = hmac_sha256_hex(get_settings().razorpay_webhook_secret, body)
    return body, {
        "Content-Type": "application/json",
        "X-Razorpay-Signature": signature,
        "X-Razorpay-Event-Id": f"evt_matrix_{int(time.time() * 1e6)}",
    }


def _store_id(ctx: Ctx) -> dict[str, str]:
    return {"id": str(ctx.target.store_id)}


ROUTE_FIXTURES: dict[str, RouteFixture] = {
    "GET /v1/users/{id}": RouteFixture(path_params=_target_owner_id),
    "PATCH /v1/users/{id}": RouteFixture(
        path_params=_target_owner_id, body=lambda _ctx: {"name": "Renamed by test"}
    ),
    "GET /v1/farmers/{id}": RouteFixture(path_params=_target_farmer_id),
    "POST /v1/farmers": RouteFixture(body=_farmer_body),
    "PATCH /v1/farmers/{id}": RouteFixture(
        path_params=_target_farmer_id, body=lambda _ctx: {"landmark": "Matrix"}
    ),
    "POST /v1/farmers/{id}/farms": RouteFixture(
        path_params=_target_farmer_id,
        body=lambda _ctx: {"name": "Matrix farm", "area_acres": "1.0"},
    ),
    "POST /v1/farmers/{id}/consents": RouteFixture(
        path_params=_target_farmer_id, body=lambda _ctx: {"purpose": "marketing", "granted": True}
    ),
    "POST /v1/farmers/{id}/phone/verify/send": RouteFixture(path_params=_target_farmer_id),
    "POST /v1/farmers/{id}/phone/verify/confirm": RouteFixture(
        path_params=_target_farmer_id, body=lambda _ctx: {"code": "000000"}
    ),
    "POST /v1/farmers/phone/verify/send": RouteFixture(
        body=lambda _ctx: {"phone": "+919000177002"}
    ),
    "POST /v1/farmers/phone/verify/confirm": RouteFixture(
        body=lambda _ctx: {"phone": "+919000177002", "code": "000000"}
    ),
    "PATCH /v1/farms/{id}": RouteFixture(
        path_params=_target_farm_id, body=lambda _ctx: {"name": "Matrix farm"}
    ),
    "DELETE /v1/farms/{id}": RouteFixture(path_params=_target_farm_id),
    "POST /v1/farms/{id}/crop-plots": RouteFixture(
        path_params=_target_farm_id,
        body=lambda ctx: {
            "crop_id": str(ctx.target.crop_id),
            "season": "kharif",
            "sowing_date": "2026-07-01",
        },
    ),
    "PATCH /v1/crop-plots/{id}": RouteFixture(
        path_params=_target_plot_id, body=lambda _ctx: {"stage": "sown"}
    ),
    "DELETE /v1/crop-plots/{id}": RouteFixture(path_params=_target_plot_id),
    "POST /v1/sync": RouteFixture(
        body=lambda _ctx: {"device_id": "matrix", "cursor": None, "ops": []}
    ),
    "POST /v1/uploads": RouteFixture(
        body=lambda _ctx: {
            "sha256": "0" * 64,
            "size_bytes": 10,
            "content_type": "image/jpeg",
            "purpose": "farm_photo",
            "chunk_size": 262144,
        }
    ),
    "GET /v1/uploads/{upload_id}": RouteFixture(path_params=_random_upload),
    "PUT /v1/uploads/{upload_id}/chunks/{index}": RouteFixture(path_params=_random_upload),
    "POST /v1/uploads/{upload_id}/complete": RouteFixture(path_params=_random_upload),
    "GET /v1/blobs/signed-url": RouteFixture(query={"uri": "gs://photos/nothing/here"}),
    "GET /v1/visits/{id}": RouteFixture(path_params=_target_visit_id),
    "POST /v1/visits/check-in": RouteFixture(body=_checkin_body),
    "PATCH /v1/visits/{id}": RouteFixture(
        path_params=_target_visit_id, body=lambda _ctx: {"notes": "Matrix"}
    ),
    "POST /v1/visits/{id}/photos": RouteFixture(
        path_params=_target_visit_id,
        body=lambda ctx: {
            "blob_uri": f"gs://local/{ctx.target.tenant.id}/visit_photo/{'0' * 64}",
            "taken_in_app": True,
        },
    ),
    "POST /v1/visits/{id}/confirm/request": RouteFixture(
        path_params=_target_visit_id, body=lambda _ctx: {"channel": "qr"}
    ),
    "POST /v1/visits/{id}/confirm": RouteFixture(
        path_params=_target_visit_id, body=lambda _ctx: {"channel": "sms_otp", "code": "000000"}
    ),
    "POST /v1/visits/{id}/farmer-confirm": RouteFixture(
        path_params=_target_visit_id, body=lambda _ctx: {"token": "not-a-real-token-at-all"}
    ),
    "POST /v1/visits/{id}/check-out": RouteFixture(
        path_params=_target_visit_id,
        body=lambda _ctx: {"checkout_at": "2026-09-18T12:00:00+00:00"},
    ),
    "POST /v1/visits/{id}/override/approve": RouteFixture(
        path_params=_target_visit_id, body=lambda _ctx: {}
    ),
    "POST /v1/visits/{id}/override/reject": RouteFixture(
        path_params=_target_visit_id, body=lambda _ctx: {}
    ),
    "GET /v1/officers/{id}/track": RouteFixture(
        path_params=_target_officer_id, query={"day": "2026-09-18"}
    ),
    # FA-010 / FA-011: valid bodies; business outcomes (policy, open session) are tested in
    # tests/duty, tests/location/test_batch.py and tests/policies.
    "POST /v1/duty/start": RouteFixture(
        body=lambda _ctx: {
            "device_id": "matrix",
            "app_version": "0.2.0",
            "policy_version": "2026-09-v1",
            "start_at": "2026-09-18T04:30:00Z",
            "start_point": {"lat": 18.02, "lon": 79.55, "accuracy_m": 10},
        }
    ),
    "POST /v1/duty/end": RouteFixture(
        body=lambda _ctx: {"end_at": "2026-09-18T12:30:00Z", "end_reason": "manual"}
    ),
    "POST /v1/location/batch": RouteFixture(
        body=lambda _ctx: {
            "duty_session_id": "00000000-0000-0000-0000-000000000000",
            "device_id": "matrix",
            "sent_at": "2026-09-18T05:00:00Z",
            "points": [{"ts": "2026-09-18T04:59:00Z", "lat": 18.02, "lon": 79.55, "accuracy_m": 8}],
        }
    ),
    # M3 reads: scope outcomes (404 outside the caller's store / cluster / own records) are
    # tested in tests/catalog and tests/orders.
    "GET /v1/catalog/skus/{id}": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.sku_id)}
    ),
    "GET /v1/stores/{id}/stock": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.store_id)}
    ),
    "GET /v1/orders/{id}": RouteFixture(path_params=lambda ctx: {"id": str(ctx.target.order_id)}),
    "GET /v1/farmers/{id}/khata": RouteFixture(path_params=_target_farmer_id),
    # WC-005 catalogue writes: valid bodies; business outcomes (409 / 422, drafts, approval,
    # overlaps) are tested in tests/catalog/test_writes.py, test_price_lists.py, test_import.py.
    "POST /v1/catalog/products": RouteFixture(
        body=lambda _ctx: {
            "name": "Matrix Product",
            "brand": "Matrix",
            "category": "pesticide",
            "hsn": "3808",
            "gst_rate_bp": 1800,
        }
    ),
    "PATCH /v1/catalog/products/{id}": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.product_id)},
        body=lambda _ctx: {"description": "Matrix"},
    ),
    "POST /v1/catalog/skus": RouteFixture(
        body=lambda ctx: {
            "product_id": str(ctx.target.product_id),
            "pack_size_value": "3",
            "pack_size_unit": "l",
            "mrp_paise": 100000,
        }
    ),
    "PATCH /v1/catalog/skus/{id}": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.sku_id)},
        body=lambda _ctx: {"active": True},
    ),
    "GET /v1/catalog/barcode/{code}": RouteFixture(
        path_params=lambda ctx: {"code": str(ctx.target.sku_barcode)}
    ),
    "POST /v1/catalog/label-claims": RouteFixture(
        body=lambda ctx: {
            "sku_id": str(ctx.target.sku_id),
            "crop_id": str(ctx.target.crop_id),
            "pest_or_disease_id": str(ctx.target.pest_id),
            "dose_per_acre": "100 ml",
            "dose_value": "100",
            "dose_unit": "ml",
            "phi_days": 7,
            "source_ref": "matrix",
        }
    ),
    "PATCH /v1/catalog/label-claims/{id}": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.claim_id)},
        body=lambda _ctx: {"ppe_text": "Gloves and mask"},
    ),
    "POST /v1/catalog/label-claims/{id}/approve": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.claim_id)}
    ),
    "POST /v1/catalog/label-claims/{id}/retire": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.claim_id)}
    ),
    "GET /v1/catalog/label-claims/{id}/history": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.claim_id)}
    ),
    "PUT /v1/catalog/price-lists": RouteFixture(
        body=lambda ctx: {
            "store_id": None,
            "items": [
                {"sku_id": str(ctx.target.sku_id), "price_paise": 1, "effective_from": "2031-01-01"}
            ],
        }
    ),
    "POST /v1/catalog/import/products": RouteFixture(
        body=lambda _ctx: {"csv": "brand,product_name\n", "dry_run": True}
    ),
    "POST /v1/catalog/import/label-claims": RouteFixture(
        body=lambda _ctx: {"csv": "sku_barcode,crop_code\n", "dry_run": True}
    ),
    # FA-020 / ST-003 / ST-005 / ST-007 / FA-022 writes: business outcomes (scope 404s,
    # 409 stock / transition / amount problems, 402 credit) in tests/orders, tests/stock,
    # tests/khata.
    "POST /v1/orders": RouteFixture(
        body=lambda ctx: {
            "farmer_id": str(ctx.target.farmer.id),
            "lines": [{"sku_id": str(ctx.target.sku_id), "qty": "1"}],
        }
    ),
    "POST /v1/orders/{id}/status": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.order_id)},
        body=lambda _ctx: {"status": "packed"},
    ),
    "GET /v1/stores/{id}/order-queue": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.store_id)}
    ),
    "POST /v1/stores/{id}/stock/receipts": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.store_id)},
        body=lambda ctx: {
            "lines": [
                {
                    "sku_id": str(ctx.target.sku_id),
                    "batch_no": "MATRIX",
                    "qty": "1",
                    "cost_paise": 1,
                }
            ]
        },
    ),
    "POST /v1/stores/{id}/stock/write-offs": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.store_id)},
        body=lambda _ctx: {"lines": [{"batch_id": str(uuid.uuid4()), "qty": "1"}]},
    ),
    "POST /v1/stores/{id}/stock/adjustments": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.store_id)},
        body=lambda _ctx: {
            "reason": "matrix",
            "lines": [{"batch_id": str(uuid.uuid4()), "counted_qty": "1"}],
        },
    ),
    "POST /v1/stock/transfers": RouteFixture(
        body=lambda ctx: {
            "from_store_id": str(ctx.target.store_id),
            "to_store_id": str(uuid.uuid4()),
            "lines": [{"batch_id": str(uuid.uuid4()), "qty": "1"}],
        }
    ),
    "PUT /v1/farmers/{id}/credit-limit": RouteFixture(
        path_params=_target_farmer_id,
        body=lambda ctx: {"store_id": str(ctx.target.store_id), "limit_paise": 100_000},
    ),
    "POST /v1/farmers/{id}/khata/entries": RouteFixture(
        path_params=_target_farmer_id,
        body=lambda _ctx: {"type": "credit", "amount_paise": 100, "reason": "matrix"},
    ),
    "POST /v1/credit-approvals/{id}/approve": RouteFixture(
        path_params=lambda _ctx: {"id": str(uuid.uuid4())}
    ),
    "POST /v1/credit-approvals/{id}/reject": RouteFixture(
        path_params=lambda _ctx: {"id": str(uuid.uuid4())}
    ),
    # FA-021 / SEC-023 / ST-001 / ST-002 / ST-006: business outcomes (amounts, stock, scope)
    # are tested in tests/payments, tests/webhooks, tests/invoices and tests/dayclose.
    "POST /v1/payments": RouteFixture(
        body=lambda ctx: {"order_id": str(ctx.target.order_id), "mode": "upi_qr", "amount_paise": 1}
    ),
    "GET /v1/payments/{id}": RouteFixture(path_params=lambda _ctx: {"id": NO_SUCH_ID}),
    "POST /v1/webhooks/razorpay": RouteFixture(raw=_signed_webhook),
    "GET /v1/invoices/{id}": RouteFixture(path_params=lambda _ctx: {"id": NO_SUCH_ID}),
    "GET /v1/invoices/{id}/pdf": RouteFixture(path_params=lambda _ctx: {"id": NO_SUCH_ID}),
    "POST /v1/invoices/{id}/share": RouteFixture(
        path_params=lambda _ctx: {"id": NO_SUCH_ID}, body=lambda _ctx: {"channel": "sms"}
    ),
    "POST /v1/stores/{id}/pos/sales": RouteFixture(
        path_params=_store_id,
        body=lambda ctx: {
            "lines": [{"sku_id": str(ctx.target.sku_id), "qty": "1"}],
            "payment": {"mode": "card_terminal", "reference_note": "matrix"},
        },
    ),
    "GET /v1/stores/{id}/day-summary": RouteFixture(path_params=_store_id),
    "POST /v1/stores/{id}/day-close": RouteFixture(
        path_params=_store_id,
        body=lambda _ctx: {"business_date": "2026-01-01", "cash_counted_paise": 0},
    ),
    "POST /v1/stores/{id}/day-close/{close_id}/reopen": RouteFixture(
        path_params=lambda ctx: {"id": str(ctx.target.store_id), "close_id": NO_SUCH_ID},
        body=lambda _ctx: {"reason": "matrix"},
    ),
    "POST /v1/policies/location/accept": RouteFixture(
        body=lambda _ctx: {
            "version": "2026-09-v1",
            "text_hash": "0" * 64,
            "device_id": "matrix",
            "app_version": "0.2.0",
        }
    ),
}


def _fixture_for(op: Operation) -> RouteFixture:
    fx = ROUTE_FIXTURES.get(op.id)
    if fx is None:
        if op.has_path_params:
            pytest.fail(f"{op.id} takes path parameters; add a RouteFixture in {__file__}")
        fx = RouteFixture()
    return fx


async def call(
    client: AsyncClient,
    op: Operation,
    ctx: Ctx,
    headers: dict[str, str] | None = None,
    *,
    path_params: dict[str, str] | None = None,
) -> Response:
    fx = _fixture_for(op)
    params = path_params if path_params is not None else fx.path_params(ctx)
    url = op.path.format(**params)
    if fx.raw is not None:
        content, extra = fx.raw(ctx)
        return await client.request(
            op.method.upper(),
            url,
            params=fx.query or None,
            content=content,
            headers={**(headers or {}), **extra},
        )
    body = fx.body(ctx)
    return await client.request(
        op.method.upper(), url, params=fx.query or None, json=body, headers=headers or {}
    )


def _assert_forbidden(resp: Response) -> None:
    assert resp.status_code == 403, resp.text
    assert resp.headers["content-type"].startswith(PROBLEM_MEDIA_TYPE)
    body = resp.json()
    assert body["code"] == "forbidden"
    assert body["status"] == 403
    assert "items" not in body


def _assert_not_rejected(resp: Response) -> None:
    assert resp.status_code not in (401, 403), f"{resp.status_code}: {resp.text}"


def _no_tenant_leak(resp: Response, other: SeededTenant) -> None:
    """Nothing of tenant B in the response (a problem ``instance`` only echoes the request path)."""
    text = resp.text
    if resp.headers.get("content-type", "").startswith(PROBLEM_MEDIA_TYPE):
        body = resp.json()
        body.pop("instance", None)
        text = json.dumps(body)
    assert str(other.tenant.id) not in text
    for user in other.everyone:
        assert str(user.id) not in text
        assert user.phone not in text
    for farmer in other.farmers:
        assert str(farmer.id) not in text
        assert farmer.phone not in text


# --------------------------------------------------------------------------- contract shape
def test_contract_has_operations() -> None:
    assert PROTECTED and PUBLIC, "openapi.yaml must contain protected and public operations"


@pytest.mark.parametrize("op", OPERATIONS, ids=[op.id for op in OPERATIONS])
def test_every_operation_declares_exactly_one_policy(op: Operation) -> None:
    if op.public:
        assert not op.roles, f"{op.id} is public and must not list x-roles"
    else:
        assert op.roles, f"{op.id} has neither x-public nor x-roles"
        assert op.roles <= set(ROLES), f"{op.id} lists unknown roles {op.roles - set(ROLES)}"
    if op.self_param is not None:
        assert not op.public and op.self_param in op.path


# --------------------------------------------------------------------------- role matrix
@pytest.mark.parametrize("role", ROLES)
@pytest.mark.parametrize("op", PROTECTED, ids=[op.id for op in PROTECTED])
async def test_role_matrix(
    client: AsyncClient, world: World, bearer: Bearer, op: Operation, role: str
) -> None:
    actor = world.a.user(role)
    ctx = Ctx(actor=actor, target=world.a)
    resp = await call(client, op, ctx, bearer(actor))
    if role in op.roles:
        _assert_not_rejected(resp)
    else:
        _assert_forbidden(resp)


SELF_OPS = [op for op in PROTECTED if op.self_param]


@pytest.mark.parametrize("role", ROLES)
@pytest.mark.parametrize("op", SELF_OPS, ids=[op.id for op in SELF_OPS])
async def test_self_access_is_allowed_for_every_role(
    client: AsyncClient, world: World, bearer: Bearer, op: Operation, role: str
) -> None:
    """``x-self`` operations: any authenticated user may address their own record."""
    actor = world.a.user(role)
    assert op.self_param is not None
    resp = await call(
        client,
        op,
        Ctx(actor=actor, target=world.a),
        bearer(actor),
        path_params={op.self_param: str(actor.id)},
    )
    assert resp.status_code < 300, resp.text
    assert resp.json()["id"] == str(actor.id)


# --------------------------------------------------------------------------- cross tenant
def _an_allowed_actor(world: World, op: Operation) -> User:
    role = UserRole.OWNER if UserRole.OWNER.value in op.roles else UserRole(sorted(op.roles)[0])
    return world.a.user(role)


@pytest.mark.parametrize("op", WITH_ID, ids=[op.id for op in WITH_ID])
async def test_cross_tenant_id_is_not_found(
    client: AsyncClient, world: World, bearer: Bearer, op: Operation
) -> None:
    """A tenant-A token addressing a tenant-B resource id gets 404 or 403, never data."""
    actor = _an_allowed_actor(world, op)
    resp = await call(client, op, Ctx(actor=actor, target=world.b), bearer(actor))
    assert resp.status_code in (403, 404), resp.text
    _no_tenant_leak(resp, world.b)


LISTS = [op for op in PROTECTED if op.method == "get" and not op.has_path_params]


@pytest.mark.parametrize("op", LISTS, ids=[op.id for op in LISTS])
async def test_collections_never_contain_other_tenants(
    client: AsyncClient, world: World, bearer: Bearer, op: Operation
) -> None:
    actor = _an_allowed_actor(world, op)
    resp = await call(client, op, Ctx(actor=actor, target=world.a), bearer(actor))
    _assert_not_rejected(resp)
    _no_tenant_leak(resp, world.b)
    if not resp.headers.get("content-type", "").startswith(
        ("application/json", PROBLEM_MEDIA_TYPE)
    ):
        return  # file downloads (CSV export): the leak check above covers them
    body = resp.json()
    for item in body.get("items", []):
        assert item.get("tenant_id", str(world.a.tenant.id)) == str(world.a.tenant.id)


# --------------------------------------------------------------------------- authentication
@pytest.mark.parametrize("op", PROTECTED, ids=[op.id for op in PROTECTED])
async def test_protected_operation_without_token(
    client: AsyncClient, world: World, op: Operation
) -> None:
    resp = await call(client, op, Ctx(actor=world.a.owner, target=world.a))
    assert resp.status_code == 401, resp.text
    assert resp.json()["code"] == "unauthenticated"
    assert resp.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("op", PUBLIC, ids=[op.id for op in PUBLIC])
async def test_public_operation_needs_no_token(
    client: AsyncClient, world: World, op: Operation
) -> None:
    resp = await call(client, op, Ctx(actor=world.a.owner, target=world.a))
    _assert_not_rejected(resp)


async def test_unknown_user_token_is_401(client: AsyncClient, world: World, bearer: Bearer) -> None:
    import uuid

    ghost = User(
        id=uuid.uuid4(),
        tenant_id=world.a.tenant.id,
        phone="+919999999999",
        name="Ghost",
        role=UserRole.OWNER,
    )
    resp = await client.get("/v1/me", headers=bearer(ghost))
    assert resp.status_code == 401
    assert resp.json()["code"] == "unauthenticated"


async def test_disabled_user_token_is_401(
    client: AsyncClient, world: World, bearer: Bearer, db_session: Any
) -> None:
    owner = world.a.owner
    headers = bearer(owner)
    owner.status = UserStatus.DISABLED
    await db_session.flush()
    resp = await client.get("/v1/users", headers=headers)
    assert resp.status_code == 401, resp.text
    assert resp.json()["code"] == "user_disabled"
    assert resp.headers["www-authenticate"] == "Bearer"


# --------------------------------------------------------------------------- logging
async def test_forbidden_call_is_logged_without_pii(
    client: AsyncClient, world: World, bearer: Bearer, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.WARNING, logger="farmerapp.auth.policy")
    officer = world.a.user(UserRole.FIELD_OFFICER)
    resp = await client.get("/v1/users", headers=bearer(officer))
    _assert_forbidden(resp)

    records = [r for r in caplog.records if r.name == "farmerapp.auth.policy"]
    assert len(records) == 1, [r.msg for r in records]
    record = records[0]
    assert record.levelno == logging.WARNING
    event = record.msg if isinstance(record.msg, dict) else {"event": record.getMessage()}
    assert event["event"] == "authz_forbidden"
    assert event["actor_id"] == str(officer.id)
    assert event["role"] == "field_officer"
    assert event["tenant_id"] == str(officer.tenant_id)
    assert event["method"] == "GET"
    assert event["route"] == "/v1/users"
    text = str(record.msg)
    assert officer.phone not in text
    assert officer.name not in text
