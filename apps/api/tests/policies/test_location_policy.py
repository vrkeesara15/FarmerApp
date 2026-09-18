"""FA-011 / VV-010: the versioned location policy text, its acceptance record (version,
timestamp, device, app version, text hash), stale text refused, and a tenant setting bump
invalidating earlier acceptances."""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.location.models import LOCATION_POLICY_KEY, PolicyAcceptance
from farmerapp.policies import service
from farmerapp.policies.location_policy import (
    LANGUAGES,
    POINTS_PER_LANGUAGE,
    known_versions,
    latest_known_version,
    policy_for,
    text_hash,
)
from farmerapp.tenants.settings import DEFAULT_LOCATION_POLICY_VERSION
from tests.authz.conftest import Bearer
from tests.duty.conftest import APP_VERSION, DEVICE, DutyCtx, set_tenant_settings
from tests.sync.conftest import op, sync

NEW_VERSION = "2026-10-v2"


# ------------------------------------------------------------------ the text module
def test_policy_texts_have_four_points_in_five_languages() -> None:
    versions = known_versions()
    assert DEFAULT_LOCATION_POLICY_VERSION in versions
    assert latest_known_version() == DEFAULT_LOCATION_POLICY_VERSION
    text = versions[DEFAULT_LOCATION_POLICY_VERSION]
    assert set(text) == set(LANGUAGES) == {"en", "te", "kn", "hi", "mr"}
    for language in LANGUAGES:
        assert len(text[language]) == POINTS_PER_LANGUAGE
        assert all(point.strip() for point in text[language])
    assert "on duty" in text["en"][0] and "off duty" in text["en"][1]


def test_text_hash_binds_version_and_text() -> None:
    policy = policy_for(DEFAULT_LOCATION_POLICY_VERSION)
    assert policy.text_hash == text_hash(DEFAULT_LOCATION_POLICY_VERSION, policy.text)
    assert len(policy.text_hash) == 64 and int(policy.text_hash, 16) >= 0
    other = policy_for(NEW_VERSION)  # unknown to the module: latest text under that version
    assert other.version == NEW_VERSION and other.text == policy.text
    assert other.text_hash != policy.text_hash
    edited = {**policy.text, "en": [*policy.text["en"][:3], "changed"]}
    assert text_hash(DEFAULT_LOCATION_POLICY_VERSION, edited) != policy.text_hash


# ------------------------------------------------------------------ GET
async def test_get_policy_serves_the_tenant_version_to_every_role(
    client: AsyncClient, dctx: DutyCtx, bearer: Bearer, db_session: AsyncSession
) -> None:
    resp = await client.get("/v1/policies/location", headers=dctx.headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    expected = policy_for(DEFAULT_LOCATION_POLICY_VERSION)
    assert body["version"] == DEFAULT_LOCATION_POLICY_VERSION
    assert body["text_hash"] == expected.text_hash
    assert body["text"] == expected.text
    for role in (UserRole.STORE_MANAGER, UserRole.FARMER, UserRole.OWNER, UserRole.AGRONOMIST):
        resp = await client.get("/v1/policies/location", headers=bearer(dctx.world.a.user(role)))
        assert resp.status_code == 200, (role, resp.text)
    await set_tenant_settings(db_session, dctx.tenant, location_policy_version=NEW_VERSION)
    resp = await client.get("/v1/policies/location", headers=dctx.headers)
    assert resp.json()["version"] == NEW_VERSION
    assert resp.json()["text_hash"] == policy_for(NEW_VERSION).text_hash


# ------------------------------------------------------------------ accept
async def test_accept_stores_version_timestamp_device_and_hash(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession
) -> None:
    resp = await client.post(
        "/v1/policies/location/accept", json=dctx.policy_body(), headers=dctx.headers
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["user_id"] == str(dctx.officer.id)
    assert body["policy_key"] == LOCATION_POLICY_KEY
    assert body["version"] == DEFAULT_LOCATION_POLICY_VERSION
    assert body["accepted_at"] == dctx.now.isoformat().replace("+00:00", "Z")
    assert body["device_id"] == DEVICE and body["app_version"] == APP_VERSION
    assert body["text_hash"] == policy_for(DEFAULT_LOCATION_POLICY_VERSION).text_hash
    row = await db_session.get_one(PolicyAcceptance, uuid.UUID(body["id"]))
    assert row.tenant_id == dctx.tenant_id and row.accepted_at == dctx.now
    latest = await service.latest_acceptance(db_session, dctx.officer)
    assert latest is not None and latest.id == row.id
    assert await service.has_accepted(db_session, dctx.officer, DEFAULT_LOCATION_POLICY_VERSION)
    assert not await service.has_accepted(db_session, dctx.officer, NEW_VERSION)


async def test_accept_is_append_only_and_the_latest_counts(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession
) -> None:
    first = await client.post(
        "/v1/policies/location/accept", json=dctx.policy_body(), headers=dctx.headers
    )
    dctx.clock.advance(timedelta(minutes=5))
    second = await client.post(
        "/v1/policies/location/accept", json=dctx.policy_body(), headers=dctx.headers
    )
    assert first.status_code == 201 and second.status_code == 201
    assert first.json()["id"] != second.json()["id"]
    ids = (
        (
            await db_session.execute(
                select(PolicyAcceptance.id).where(PolicyAcceptance.user_id == dctx.officer.id)
            )
        )
        .scalars()
        .all()
    )
    assert {uuid.UUID(first.json()["id"]), uuid.UUID(second.json()["id"])} <= set(ids)
    latest = await service.latest_acceptance(db_session, dctx.officer)
    assert latest is not None and str(latest.id) == second.json()["id"]


@pytest.mark.parametrize(
    "override",
    [{"text_hash": "0" * 64}, {"version": "2025-01-v0"}, {"version": NEW_VERSION}],
)
async def test_accept_with_a_stale_hash_or_version_is_rejected(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession, override: dict[str, str]
) -> None:
    body = {**dctx.policy_body(), **override}
    if override.get("version") == NEW_VERSION:
        body["text_hash"] = policy_for(
            NEW_VERSION
        ).text_hash  # right hash, not the tenant's version
    resp = await client.post("/v1/policies/location/accept", json=body, headers=dctx.headers)
    assert resp.status_code == 422, resp.text
    assert resp.json()["code"] == "policy_version_stale"
    assert resp.json()["current_version"] == DEFAULT_LOCATION_POLICY_VERSION
    count = await db_session.scalar(
        select(PolicyAcceptance.id).where(
            PolicyAcceptance.user_id == dctx.officer.id, PolicyAcceptance.accepted_at == dctx.now
        )
    )
    assert count is None


async def test_accept_replay_with_idempotency_key_returns_the_same_row(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession
) -> None:
    headers = {**dctx.headers, "Idempotency-Key": "accept-1"}
    first = await client.post(
        "/v1/policies/location/accept", json=dctx.policy_body(), headers=headers
    )
    second = await client.post(
        "/v1/policies/location/accept", json=dctx.policy_body(), headers=headers
    )
    assert first.status_code == 201 and second.json() == first.json()
    rows = (
        await db_session.execute(
            select(PolicyAcceptance.id).where(
                PolicyAcceptance.user_id == dctx.officer.id,
                PolicyAcceptance.accepted_at == dctx.now,
            )
        )
    ).all()
    assert len(rows) == 1


# ------------------------------------------------------------------ VV-010 setting bump
async def test_bumping_the_tenant_version_invalidates_earlier_acceptances(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession
) -> None:
    await client.post("/v1/policies/location/accept", json=dctx.policy_body(), headers=dctx.headers)
    current = await client.get("/v1/duty/current", headers=dctx.headers)
    assert current.json()["policy_accepted"] is True

    await set_tenant_settings(db_session, dctx.tenant, location_policy_version=NEW_VERSION)
    current = await client.get("/v1/duty/current", headers=dctx.headers)
    assert current.json() == {
        "session": None,
        "policy_version": NEW_VERSION,
        "policy_accepted": False,
    }
    resp = await client.post(
        "/v1/duty/start", json=dctx.start_body(policy_version=NEW_VERSION), headers=dctx.headers
    )
    assert resp.status_code == 422 and resp.json()["code"] == "policy_not_accepted"
    # The old text hash is refused for the new version; the served one is accepted.
    stale = await client.post(
        "/v1/policies/location/accept",
        json={**dctx.policy_body(), "version": NEW_VERSION},
        headers=dctx.headers,
    )
    assert stale.status_code == 422 and stale.json()["code"] == "policy_version_stale"
    fresh = await client.post(
        "/v1/policies/location/accept", json=dctx.policy_body(NEW_VERSION), headers=dctx.headers
    )
    assert fresh.status_code == 201 and fresh.json()["version"] == NEW_VERSION
    current = await client.get("/v1/duty/current", headers=dctx.headers)
    assert current.json()["policy_accepted"] is True
    resp = await client.post(
        "/v1/duty/start", json=dctx.start_body(policy_version=NEW_VERSION), headers=dctx.headers
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["policy_version"] == NEW_VERSION


# ------------------------------------------------------------------ sync (offline first run)
async def test_sync_policy_acceptance_for_the_offline_first_run(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession
) -> None:
    acceptance_id = uuid.uuid4()
    tapped_at = dctx.now - timedelta(hours=2)
    create = op(
        "policy_acceptance",
        "create",
        dctx.policy_body(),
        entity_id=acceptance_id,
        client_ts=tapped_at,
    )
    body = await sync(client, dctx.ctx, [create], headers=dctx.headers)
    result = body["results"][0]
    assert result["status"] == "applied" and result["version"] == 1, result
    assert result["server"]["id"] == str(acceptance_id)
    assert result["server"]["accepted_at"] == tapped_at.isoformat().replace("+00:00", "Z")
    assert result["server"]["device_id"] == DEVICE
    assert ("policy_acceptance", str(acceptance_id)) in {
        (c["entity"], c["entity_id"]) for c in body["changes"]
    }
    replay = await sync(client, dctx.ctx, [create], headers=dctx.headers)
    assert replay["results"][0]["status"] == "duplicate"
    again = await sync(
        client,
        dctx.ctx,
        [op("policy_acceptance", "create", dctx.policy_body(), entity_id=acceptance_id)],
        headers=dctx.headers,
    )
    assert again["results"][0]["status"] == "conflict"
    assert again["results"][0]["server"]["id"] == str(acceptance_id)

    stale = op("policy_acceptance", "create", {**dctx.policy_body(), "text_hash": "f" * 64})
    body = await sync(client, dctx.ctx, [stale], headers=dctx.headers)
    assert body["results"][0]["status"] == "rejected"
    assert body["results"][0]["error"]["code"] == "policy_version_stale"
    # A device that tapped agree "in the future" is recorded at server time.
    ahead = op(
        "policy_acceptance", "create", dctx.policy_body(), client_ts=dctx.now + timedelta(days=1)
    )
    body = await sync(client, dctx.ctx, [ahead], headers=dctx.headers)
    assert body["results"][0]["server"]["accepted_at"] == dctx.now.isoformat().replace(
        "+00:00", "Z"
    )
    # Update / delete never apply to the append-only record.
    body = await sync(
        client,
        dctx.ctx,
        [
            op(
                "policy_acceptance",
                "update",
                {"version": "x"},
                entity_id=acceptance_id,
                base_version=1,
            )
        ],
        headers=dctx.headers,
    )
    assert body["results"][0]["status"] == "rejected"
    assert body["results"][0]["error"]["code"] == "unsupported_action"
