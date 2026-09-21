"""DX-011 nightly evaluation (manifest in the corpus bucket, rolled back, evaluation_run with
per-crop / per-problem metrics, > 5 point drop alert) and the AN-007 quality API."""

from __future__ import annotations

import csv
import io
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.diagnosis.images import synthetic_leaf
from farmerapp.diagnosis.models import Diagnosis
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.mlops.evaluation import manifest_uri, nightly_evaluation, parse_manifest
from farmerapp.mlops.models import EvaluationRun
from farmerapp.notifications.models import Notification
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import Bearer, World
from tests.logcontract import assert_fields, capture, one_event

REPO = Path(__file__).resolve().parents[4]
CI_MANIFEST = REPO / "ml" / "eval" / "testset" / "ci" / "manifest.csv"
KEY = "eval/heldout/manifest.csv"


def _manifest(rows: list[dict[str, str]]) -> bytes:
    out = io.StringIO()
    writer = csv.DictWriter(
        out, fieldnames=["image", "crop", "true_problem", "district", "season"], lineterminator="\n"
    )
    writer.writeheader()
    writer.writerows(rows)
    return out.getvalue().encode()


def _ci_rows() -> list[dict[str, str]]:
    return list(csv.DictReader(io.StringIO(CI_MANIFEST.read_text())))


async def _put_manifest(blobs: BlobStore, rows: list[dict[str, str]]) -> str:
    # One field photo next to the manifest, referenced by a relative path.
    await blobs.put(
        "eval/heldout/img/bph-1.jpg", synthetic_leaf("paddy_bph", 950), content_type="image/jpeg"
    )
    return await blobs.put(KEY, _manifest(rows), content_type="text/csv")


async def test_nightly_evaluation_records_a_run_and_alerts_on_a_drop(
    db_session: AsyncSession,
    world: World,
    services: DiagnosisServices,
    blobs: BlobStore,
    caplog: pytest.LogCaptureFixture,
) -> None:
    capture(caplog)
    rows = [
        *_ci_rows(),
        {
            "image": "img/bph-1.jpg",
            "crop": "paddy",
            "true_problem": "paddy_bph",
            "district": "Warangal",
            "season": "kharif",
        },
    ]
    uri = await _put_manifest(blobs, rows)
    diagnoses_before = await db_session.scalar(select(func.count()).select_from(Diagnosis))
    first = await nightly_evaluation(
        db_session,
        tenant_id=world.a.tenant.id,
        services=services,
        manifest=uri,
        corpus_blobs=blobs,
        now=datetime(2026, 9, 20, 21, 0, tzinfo=UTC),
    )
    assert first.status == "ok", first.error
    assert first.cases == 19 and first.top1_accuracy is not None and first.top1_accuracy > 0.9
    assert first.per_crop["paddy"]["cases"] >= 15 and "unknown" in first.per_crop
    assert set(first.per_problem) >= {"paddy_bph", "paddy_stem_borer", "out_of_scope"}
    assert first.corpus_answer_share is not None and first.escalation_rate is not None
    assert first.hallucinated_out_of_scope == 0
    assert first.previous_run_id is None and first.top1_delta_points is None
    assert not first.alerted
    # rolled back: the evaluation wrote no diagnosis
    assert await db_session.scalar(select(func.count()).select_from(Diagnosis)) == diagnoses_before
    done = one_event(caplog, "diagnosis_eval_done")
    assert_fields(done, tenant_id=str, run_id=str, cases=int, top1_accuracy=float)

    # The labels of the second night are wrong for every BPH / stem borer row: accuracy falls.
    swapped = [
        {
            **r,
            "true_problem": {"paddy_bph": "paddy_stem_borer", "paddy_stem_borer": "paddy_bph"}.get(
                r["true_problem"], r["true_problem"]
            ),
        }
        for r in rows
    ]
    await blobs.put(KEY, _manifest(swapped), content_type="text/csv")
    second = await nightly_evaluation(
        db_session,
        tenant_id=world.a.tenant.id,
        services=services,
        manifest=uri,
        corpus_blobs=blobs,
        now=datetime(2026, 9, 21, 21, 0, tzinfo=UTC),
    )
    assert second.previous_run_id == first.id
    assert second.top1_delta_points is not None and second.top1_delta_points < -5
    assert second.alerted
    drop = one_event(caplog, "diagnosis_eval_accuracy_drop")
    assert_fields(drop, tenant_id=str, run_id=str, delta_points=float, threshold_points=float)
    notes = (
        (
            await db_session.execute(
                select(Notification).where(Notification.kind == "diagnosis_eval_drop")
            )
        )
        .scalars()
        .all()
    )
    assert {n.user_id for n in notes} >= {
        world.a.user(UserRole.AGRONOMIST).id,
        world.a.owner.id,
    }
    assert notes[0].data["evaluation_run_id"] == str(second.id)


async def test_small_changes_do_not_alert(
    db_session: AsyncSession, world: World, services: DiagnosisServices, blobs: BlobStore
) -> None:
    uri = await _put_manifest(blobs, _ci_rows())
    kwargs = {"tenant_id": world.a.tenant.id, "services": services, "corpus_blobs": blobs}
    await nightly_evaluation(db_session, manifest=uri, **kwargs)  # type: ignore[arg-type]
    again = await nightly_evaluation(db_session, manifest=uri, **kwargs)  # type: ignore[arg-type]
    assert again.top1_delta_points == 0 and not again.alerted


async def test_a_missing_manifest_records_a_failed_run(
    db_session: AsyncSession, world: World, services: DiagnosisServices, blobs: BlobStore
) -> None:
    run = await nightly_evaluation(
        db_session,
        tenant_id=world.a.tenant.id,
        services=services,
        manifest="gs://local/eval/none.csv",
        corpus_blobs=blobs,
    )
    assert run.status == "failed" and run.error and "BlobNotFound" in run.error
    assert run.top1_accuracy is None


def test_manifest_uri_and_parsing() -> None:
    assert manifest_uri("corpus-b", "eval/x.csv") == "gs://corpus-b/eval/x.csv"
    assert manifest_uri("corpus-b", "gs://other/y.csv") == "gs://other/y.csv"
    rows = parse_manifest("image,crop,true_problem\nx.jpg,,out_of_scope\n")
    assert rows[0].crop == "unknown" and rows[0].district is None
    with pytest.raises(ValueError, match="true_problem"):
        parse_manifest("image,crop\nx.jpg,paddy\n")


# ------------------------------------------------------------------ AN-007 API
async def test_quality_summary_api(
    client: AsyncClient,
    bearer: Bearer,
    db_session: AsyncSession,
    world: World,
    services: DiagnosisServices,
    blobs: BlobStore,
) -> None:
    now = datetime.now(UTC)
    farmer = world.a.farmer
    tid = world.a.tenant.id

    def row(status: str, source: str | None, **extra: object) -> Diagnosis:
        return Diagnosis(
            tenant_id=tid,
            subject="farmer",
            farmer_id=farmer.id,
            images=[],
            status=status,
            source=source,
            model_versions={},
            **extra,
        )

    db_session.add_all(
        [
            row("answered", "corpus", created_at=now - timedelta(hours=5)),
            row("answered", "corpus", created_at=now - timedelta(hours=4)),
            row(
                "confirmed",
                "agronomist",
                created_at=now - timedelta(hours=30),
                reviewed_at=now - timedelta(hours=20),
            ),
            row(
                "corrected",
                "agronomist",
                created_at=now - timedelta(hours=60),
                reviewed_at=now - timedelta(hours=10),
            ),
            row("provisional", "llm", created_at=now - timedelta(hours=30)),
            row(
                "out_of_scope",
                None,
                created_at=now - timedelta(hours=2),
                out_of_scope_reason="not_a_plant",
            ),
            row("answered", "corpus", created_at=now - timedelta(days=90)),  # outside 30 days
        ]
    )
    await db_session.flush()
    uri = await _put_manifest(blobs, _ci_rows())
    run = await nightly_evaluation(
        db_session, tenant_id=tid, services=services, manifest=uri, corpus_blobs=blobs
    )
    resp = await client.get("/v1/diagnoses/quality", headers=bearer(world.a.user("agronomist")))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    seeded = await db_session.scalar(
        select(func.count())
        .select_from(Diagnosis)
        .where(Diagnosis.tenant_id == tid, Diagnosis.created_at >= now - timedelta(days=29))
    )
    assert body["requests"] == seeded
    assert body["answered_by_corpus"] >= 2 and 0 < body["corpus_share"] <= 1
    assert body["escalated"] >= 4 and body["escalation_rate"] is not None
    review = body["review"]
    assert review["sla_hours"] == 24 and review["reviewed"] >= 2
    assert review["reviewed_within_sla"] >= 1  # 10 h; the 50 h one is outside
    assert review["open_queue"] >= 2 and review["open_overdue"] >= 1
    assert any(u["reason"] == "not_a_plant" for u in body["top_unknowns"])
    assert body["latest_evaluation"]["id"] == str(run.id)
    # DX-011 in the console: the alert threshold and top-1 accuracy per crop, on every run.
    assert body["evaluation_alert_drop_points"] == 5.0
    crops = {c["crop_code"]: c for c in body["latest_evaluation"]["crops"]}
    assert crops["paddy"]["cases"] == run.per_crop["paddy"]["cases"]
    assert crops["paddy"]["top1_accuracy"] == run.per_crop["paddy"]["top1_accuracy"]
    runs = await client.get("/v1/diagnoses/evaluations", headers=bearer(world.a.owner))
    assert [r["id"] for r in runs.json()["items"]] == [str(run.id)]
    assert [c["crop_code"] for c in runs.json()["items"][0]["crops"]] == sorted(run.per_crop)
    detail = await client.get(f"/v1/diagnoses/evaluations/{run.id}", headers=bearer(world.a.owner))
    assert detail.status_code == 200 and "paddy_bph" in detail.json()["per_problem"]
    missing = await client.get(
        f"/v1/diagnoses/evaluations/{uuid.uuid4()}", headers=bearer(world.a.owner)
    )
    assert missing.status_code == 404
    # quality is not a diagnosis id
    assert (
        await client.get("/v1/diagnoses/quality", headers=bearer(world.a.owner))
    ).status_code == 200
    stored = await db_session.scalar(select(func.count()).select_from(EvaluationRun))
    assert stored == 1


async def test_evaluate_cli_still_works(
    db_session: AsyncSession, world: World, services: DiagnosisServices
) -> None:
    """ml/eval/evaluate.py re-exports the shared logic (tests/diagnosis/test_evaluate.py)."""
    import importlib.util
    import sys

    script = REPO / "ml" / "eval" / "evaluate.py"
    spec = importlib.util.spec_from_file_location("ml_eval_evaluate_m7", script)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    assert module.evaluate is not None and module.load_manifest(CI_MANIFEST)
