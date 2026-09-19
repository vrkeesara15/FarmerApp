"""FA-026 acceptance: "demo lifecycle from creation to yield entry"."""

from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.farmers.models import CropPlot, Farm
from tests.analytics.builders import Mini
from tests.authz.conftest import Bearer
from tests.field_tokens import mint_bearer


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    return mint_bearer(app)


OBSERVED = "2026-08-20T05:00:00+00:00"


@dataclass
class Demo:
    m: Mini
    headers: dict[str, str]
    plot_id: uuid.UUID  # F1's paddy plot
    other_plot_id: uuid.UUID  # F3's (O2) cotton plot
    body: dict[str, Any]


async def _plot(session: AsyncSession, farmer_id: uuid.UUID) -> uuid.UUID:
    farm = await session.scalar(select(Farm).where(Farm.farmer_id == farmer_id))
    assert farm is not None
    plot = await session.scalar(select(CropPlot.id).where(CropPlot.farm_id == farm.id))
    assert plot is not None
    return plot


@pytest.fixture
async def demo(db_session: AsyncSession, bearer: Bearer) -> Demo:
    m = await Mini.create(db_session)
    plot = await _plot(db_session, m.farmers["f1"].id)
    other = await _plot(db_session, m.farmers["f3"].id)
    body = {
        "farmer_id": str(m.farmers["f1"].id),
        "crop_plot_id": str(plot),
        "baseline": "farmer_practice",
        "product_id": str(m.skus["own"].product_id),
        "treatment": "Own Guard 200 ml per acre at tillering",
    }
    return Demo(m=m, headers=bearer(m.user("o1")), plot_id=plot, other_plot_id=other, body=body)


async def photo(app: FastAPI, tenant_id: uuid.UUID) -> str:
    data = uuid.uuid4().bytes
    uri: str = await app.state.blobs.put(
        f"{tenant_id}/demo_plot/{hashlib.sha256(data).hexdigest()}", data, content_type="image/jpeg"
    )
    return uri


async def test_demo_lifecycle_from_creation_to_yield_entry(
    app: FastAPI, client: AsyncClient, bearer: Bearer, demo: Demo
) -> None:
    resp = await client.post("/v1/demo-plots", json=demo.body, headers=demo.headers)
    assert resp.status_code == 201, resp.text
    plot = resp.json()
    assert plot["status"] == "created" and plot["officer_id"] == str(demo.m.user("o1").id)
    pid = plot["id"]

    # Yield before activation, report before harvest: refused.
    early = await client.post(
        f"/v1/demo-plots/{pid}/yield", json={"demo_yield_kg_per_acre": "10"}, headers=demo.headers
    )
    assert early.status_code == 409 and early.json()["code"] == "demo_plot_transition_invalid"
    early = await client.post(
        f"/v1/demo-plots/{pid}/transition", json={"to": "reported"}, headers=demo.headers
    )
    assert early.status_code == 409

    resp = await client.post(
        f"/v1/demo-plots/{pid}/transition", json={"to": "active"}, headers=demo.headers
    )
    assert resp.json()["status"] == "active" and resp.json()["started_at"] is not None

    uri = await photo(app, demo.m.tid)
    resp = await client.post(
        f"/v1/demo-plots/{pid}/observations",
        json={
            "stage": "flowering",
            "side": "both",
            "observed_at": OBSERVED,
            "note": "Even stand",
            "photo_uris": [uri],
        },
        headers=demo.headers,
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["photo_uris"] == [uri]
    bad = await client.post(
        f"/v1/demo-plots/{pid}/observations",
        json={
            "stage": "flowering",
            "observed_at": OBSERVED,
            "photo_uris": [f"gs://local/{uuid.uuid4()}/demo_plot/{'0' * 64}"],
        },
        headers=demo.headers,
    )
    assert bad.status_code == 422 and bad.json()["code"] == "invalid_blob"

    resp = await client.post(
        f"/v1/demo-plots/{pid}/yield",
        json={
            "demo_yield_kg_per_acre": "2350.5",
            "practice_yield_kg_per_acre": "2100",
            "note": "Crop cut 5 m x 5 m",
        },
        headers=demo.headers,
    )
    assert resp.status_code == 200, resp.text
    harvested = resp.json()
    assert harvested["status"] == "harvested" and harvested["yield_gain_pct"] == 11.9
    resp = await client.post(
        f"/v1/demo-plots/{pid}/transition", json={"to": "reported"}, headers=demo.headers
    )
    assert resp.json()["status"] == "reported" and resp.json()["reported_at"] is not None

    detail = await client.get(f"/v1/demo-plots/{pid}", headers=demo.headers)
    body = detail.json()
    assert body["stage"] == "flowering" and body["last_observed_at"] is not None
    assert [o["stage"] for o in body["observations"]] == ["flowering"]
    # Reported: no more observations.
    late = await client.post(
        f"/v1/demo-plots/{pid}/observations",
        json={"stage": "harvest", "observed_at": OBSERVED},
        headers=demo.headers,
    )
    assert late.status_code == 409

    # Readers: the cluster head, the owner and the agronomist; O2 and the store manager not.
    for viewer in ("cluster_head", "owner", "agronomist"):
        resp = await client.get(f"/v1/demo-plots/{pid}", headers=bearer(demo.m.user(viewer)))
        assert resp.status_code == 200, viewer
    resp = await client.get(f"/v1/demo-plots/{pid}", headers=bearer(demo.m.user("o2")))
    assert resp.status_code == 404
    resp = await client.get("/v1/demo-plots", headers=bearer(demo.m.user("store_manager")))
    assert resp.status_code == 403
    listed = await client.get(
        "/v1/demo-plots", params={"status": "reported"}, headers=bearer(demo.m.user("owner"))
    )
    assert [p["id"] for p in listed.json()["items"]] == [pid]


async def test_create_rules(client: AsyncClient, demo: Demo, bearer: Bearer) -> None:
    other_farmer_plot = {**demo.body, "crop_plot_id": str(demo.other_plot_id)}
    resp = await client.post("/v1/demo-plots", json=other_farmer_plot, headers=demo.headers)
    assert resp.status_code == 404  # O2's farmer's plot is outside O1's scope
    no_comparison = {**demo.body, "baseline": "comparison_plot"}
    resp = await client.post("/v1/demo-plots", json=no_comparison, headers=demo.headers)
    assert resp.status_code == 422
    same = {
        **demo.body,
        "baseline": "comparison_plot",
        "comparison_crop_plot_id": str(demo.plot_id),
    }
    resp = await client.post("/v1/demo-plots", json=same, headers=demo.headers)
    assert resp.status_code == 422
    resp = await client.post(
        "/v1/demo-plots", json={**demo.body, "product_id": str(uuid.uuid4())}, headers=demo.headers
    )
    assert resp.status_code == 422 and resp.json()["code"] == "demo_plot_invalid"
    # Only the officer who runs a demo writes to it.
    plot = (await client.post("/v1/demo-plots", json=demo.body, headers=demo.headers)).json()
    resp = await client.post(
        f"/v1/demo-plots/{plot['id']}/transition",
        json={"to": "active"},
        headers=bearer(demo.m.user("o2")),
    )
    assert resp.status_code == 404


async def test_demo_plots_offline_through_sync(
    app: FastAPI, client: AsyncClient, demo: Demo
) -> None:
    pid, oid = uuid.uuid4(), uuid.uuid4()

    def op(
        entity: str, action: str, entity_id: uuid.UUID, payload: dict[str, Any]
    ) -> dict[str, Any]:
        return {
            "op_id": str(uuid.uuid4()),
            "entity": entity,
            "action": action,
            "entity_id": str(entity_id),
            "base_version": 0 if action == "create" else 1,
            "payload": payload,
            "client_ts": "2026-08-20T06:00:00+00:00",
        }

    ops = [
        op("demo_plot", "create", pid, demo.body),
        op("demo_plot", "update", pid, {"status": "active"}),
        op(
            "demo_observation",
            "create",
            oid,
            {
                "demo_plot_id": str(pid),
                "stage": "vegetative",
                "observed_at": OBSERVED,
                "photo_uris": [await photo(app, demo.m.tid)],
            },
        ),
    ]
    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": None, "ops": ops}, headers=demo.headers
    )
    results = resp.json()["results"]
    assert [r["status"] for r in results] == ["applied", "applied", "applied"], results
    assert results[1]["server"]["status"] == "active"
    entities = {c["entity"] for c in resp.json()["changes"]}
    assert {"demo_plot", "demo_observation"} <= entities
