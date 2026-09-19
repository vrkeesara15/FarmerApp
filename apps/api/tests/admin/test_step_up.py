"""SEC-028: admin actions need a fresh OTP (step-up token) and are audited."""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

import jwt
import pytest
import yaml
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User
from farmerapp.auth.providers import FakeProvider
from farmerapp.auth.stepup import STEP_UP_HEADER, issue_step_up_token
from tests.admin.conftest import Headers, Mint, audit_rows, problem
from tests.auth.conftest import last_code

OPENAPI = Path(__file__).resolve().parents[2] / "openapi.yaml"


def _protected(officer: User) -> list[tuple[str, str, dict[str, Any] | None]]:
    """Every step-up protected action: (method, path, body)."""
    return [
        ("POST", "/v1/users", {"phone": "+919000188002", "name": "New", "role": "agronomist"}),
        ("PATCH", f"/v1/users/{officer.id}", {"role": "cluster_head"}),
        ("PATCH", f"/v1/users/{officer.id}", {"status": "disabled"}),
        ("POST", f"/v1/users/{officer.id}/deactivate", None),
        ("POST", f"/v1/users/{officer.id}/force-logout", None),
        ("POST", f"/v1/users/{officer.id}/devices/phone-x/bind", None),
        ("POST", f"/v1/users/{officer.id}/devices/phone-x/report-lost", None),
        ("PATCH", "/v1/settings", {"geofence_radius_m": 200}),
        ("GET", "/v1/audit-logs/export", None),
        ("GET", "/v1/catalog/export?kind=products", None),
    ]


ACTIONS = [
    "create_user",
    "role_change",
    "status_change",
    "deactivate",
    "force_logout",
    "device_bind",
    "device_report_lost",
    "settings_change",
    "audit_export",
    "catalog_export",
]


@pytest.mark.parametrize("index", range(len(ACTIONS)), ids=ACTIONS)
async def test_protected_action_needs_step_up(
    client: AsyncClient,
    officer: User,
    owner: User,
    bearer: Mint,
    step_up: Callable[[User], Headers],
    index: int,
) -> None:
    method, path, body = _protected(officer)[index]
    resp = await client.request(method, path, json=body, headers=bearer(owner))
    problem_body = problem(resp, 401, "step_up_required")
    assert problem_body["step_up_url"] == "/v1/auth/step-up/send"
    # a garbage token is no better
    resp = await client.request(
        method, path, json=body, headers=bearer(owner) | {STEP_UP_HEADER: "garbage"}
    )
    problem(resp, 401, "step_up_required")
    # with a fresh step-up the action goes through (404 for the unseen device is business)
    resp = await client.request(method, path, json=body, headers=bearer(owner) | step_up(owner))
    assert resp.status_code in (200, 201, 404), resp.text


def test_contract_marks_protected_operations() -> None:
    spec = yaml.safe_load(OPENAPI.read_text())
    marked = {
        (method.upper(), path)
        for path, item in spec["paths"].items()
        for method, op in item.items()
        if isinstance(op, dict) and op.get("x-step-up")
    }
    assert marked == {
        ("POST", "/v1/users"),
        ("POST", "/v1/users/{id}/deactivate"),
        ("POST", "/v1/users/{id}/force-logout"),
        ("POST", "/v1/users/{id}/devices/{device_id}/bind"),
        ("POST", "/v1/users/{id}/devices/{device_id}/report-lost"),
        ("PATCH", "/v1/settings"),
        ("GET", "/v1/audit-logs/export"),
        ("GET", "/v1/catalog/export"),
        ("POST", "/v1/flags/rules/{rule_id}/enable"),  # M7 VA-006 rule re-enable
        ("POST", "/v1/models/releases/{id}/decision"),  # M7 DX-012 model approval
    }
    patch_user = spec["paths"]["/v1/users/{id}"]["patch"]
    assert "step_up_required" in patch_user["responses"]["401"]["description"]


async def test_rename_and_assignment_need_no_step_up(
    client: AsyncClient, officer: User, owner: User, bearer: Mint
) -> None:
    resp = await client.patch(
        f"/v1/users/{officer.id}", json={"name": "Ramesh K."}, headers=bearer(owner)
    )
    assert resp.status_code == 200, resp.text


async def test_role_check_runs_before_step_up(
    client: AsyncClient, officer: User, store_manager: User, bearer: Mint
) -> None:
    resp = await client.post(f"/v1/users/{officer.id}/force-logout", headers=bearer(store_manager))
    problem(resp, 403, "forbidden")


async def test_otp_step_up_flow(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    owner: User,
    bearer: Mint,
    db_session: AsyncSession,
) -> None:
    resp = await client.post("/v1/auth/step-up/send", headers=bearer(owner))
    assert resp.status_code == 202, resp.text
    assert resp.json()["phone_masked"].endswith(owner.phone[-4:])
    code = last_code(sms, owner.phone)

    wrong = "111111" if code != "111111" else "222222"
    resp = await client.post("/v1/auth/step-up", json={"code": wrong}, headers=bearer(owner))
    problem(resp, 401, "otp_invalid")
    resp = await client.post("/v1/auth/step-up", json={"code": code}, headers=bearer(owner))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["expires_in"] == 300
    token = body["step_up_token"]

    # single-use code
    resp = await client.post("/v1/auth/step-up", json={"code": code}, headers=bearer(owner))
    problem(resp, 404, "otp_not_found")

    resp = await client.post(
        f"/v1/users/{officer.id}/force-logout",
        headers=bearer(owner) | {STEP_UP_HEADER: token},
    )
    assert resp.status_code == 200, resp.text
    (row,) = await audit_rows(db_session, action="auth.step_up")
    assert row.actor_id == owner.id and row.entity_id == owner.id


async def test_step_up_token_expires_after_five_minutes(
    client: AsyncClient,
    officer: User,
    owner: User,
    bearer: Mint,
    step_up: Callable[[User], Headers],
    clock: FakeClock,
) -> None:
    headers = step_up(owner)
    clock.advance(299)
    resp = await client.post(
        f"/v1/users/{officer.id}/force-logout", headers=bearer(owner) | headers
    )
    assert resp.status_code == 200, resp.text
    clock.advance(2)
    resp = await client.post(
        f"/v1/users/{officer.id}/force-logout", headers=bearer(owner) | headers
    )
    problem(resp, 401, "step_up_required")


async def test_step_up_token_is_bound_to_its_user_and_type(
    client: AsyncClient,
    officer: User,
    owner: User,
    director: User,
    bearer: Mint,
    step_up: Callable[[User], Headers],
    auth_services: AuthServices,
) -> None:
    path = f"/v1/users/{officer.id}/force-logout"
    # someone else's step-up
    problem(
        await client.post(path, headers=bearer(owner) | step_up(director)), 401, "step_up_required"
    )
    # an access token is not a step-up token ...
    access = bearer(owner)["Authorization"].split(" ", 1)[1]
    resp = await client.post(path, headers=bearer(owner) | {STEP_UP_HEADER: access})
    problem(resp, 401, "step_up_required")
    # ... and a step-up token is not an access token
    stepup = issue_step_up_token(auth_services.settings, owner, auth_services.clock.now())
    resp = await client.get("/v1/me", headers={"Authorization": f"Bearer {stepup}"})
    assert resp.status_code == 401
    # a step-up token signed with another key is rejected
    forged = jwt.encode(
        jwt.decode(stepup, options={"verify_signature": False}),
        "not-the-signing-key-but-long-enough-32b",
        algorithm="HS256",
    )
    resp = await client.post(path, headers=bearer(owner) | {STEP_UP_HEADER: forged})
    problem(resp, 401, "step_up_required")
