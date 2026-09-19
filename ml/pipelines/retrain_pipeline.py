"""DX-012 Vertex AI pipelines as code (KFP v2). Compiled, never run from CI or by an agent.

Two pipelines, both ending at a **human approval gate in the API**:

``ondevice-monthly-finetune`` (monthly, per tenant)
    1. ``export-training-set`` — the API job writes the approved corpus field images as a
       training manifest to ``gs://<corpus>/training/<tenant>/<YYYYMMDD>/manifest.csv``
       (run through the ``export-training-set`` Cloud Run job, which also runs weekly).
    2. ``finetune-and-export`` — the ``ml/ondevice`` image mirrors the manifest's images,
       fine-tunes the previous model (``finetune.py``), quantises and evaluates it
       (``export.py``) and uploads ``model.tflite`` + ``metadata.json`` to
       ``gs://<corpus>/models/on-device/<version>/``.
    3. ``register-model-candidate`` — the API job records a ``model_release`` candidate (sha256
       from the bytes) and notifies the agronomists and owners.
    Gate: an agronomist or the owner approves or rejects the candidate in the console
    (``POST /v1/models/releases/{id}/decision``, step-up, audited). Apps download only approved
    models (``GET /v1/models/on-device/current``).

``encoder-reembed`` (when the embed service gets a new encoder version)
    1. ``reembed-corpus`` — stages every live corpus image's vector under the new encoder.
    2. ``diagnosis-evaluate`` — the held-out evaluation (DX-011) with the new encoder, so the
       agronomist sees the accuracy before the flip.
    Gate: a human retunes the DX-003 thresholds, moves the API pin and runs
    ``activate-encoder`` (one transaction; docs/prs/M7-farmer-p1-api.md).

API steps execute the existing Cloud Run jobs with an ``--args`` override (same image, same
service account, same database identity as the scheduled jobs), so the pipeline's own service
account only needs ``roles/run.developer`` on those jobs and object access to the corpus bucket.

Compile (from this directory)::

    uv run --no-project --with kfp==2.13.0 python retrain_pipeline.py --out compiled
"""

# No `from __future__ import annotations`: KFP reads the component annotations at runtime.

import argparse
import os
from pathlib import Path

from kfp import compiler, dsl

GCLOUD_IMAGE = "gcr.io/google.com/cloudsdktool/google-cloud-cli:slim"
#: The ml/ondevice training image (TensorFlow + LiteRT + gcloud); set at compile time. Building
#: and pushing it to Artifact Registry is part of the human Vertex AI wiring gate.
ONDEVICE_IMAGE = os.environ.get(
    "ONDEVICE_IMAGE", "asia-south1-docker.pkg.dev/farmerapp-dev/farmerapp/ondevice-train:latest"
)


_EXECUTE = 'gcloud run jobs execute "$2" --project "$0" --region "$1" --wait --args="$3"'


@dsl.container_component
def run_api_job(project: str, region: str, job: str, command: str, tenant_id: str) -> dsl.ContainerSpec:
    """Execute a Cloud Run job of the API image as ``python -m farmerapp.jobs <command>
    --tenant-id <tenant>`` and wait for it (a non-zero exit fails the step)."""
    return dsl.ContainerSpec(
        image=GCLOUD_IMAGE,
        command=["bash", "-ceu", 'args="$3,--tenant-id,$4"; set -- "$0" "$1" "$2" "$args"; ' + _EXECUTE],
        args=[project, region, job, command, tenant_id],
    )


@dsl.container_component
def register_candidate(
    project: str, region: str, job: str, tenant_id: str, artifact_uri: str, metadata_uri: str
) -> dsl.ContainerSpec:
    """``register-model-candidate`` for the uploaded model (the approval gate is in the API)."""
    return dsl.ContainerSpec(
        image=GCLOUD_IMAGE,
        command=[
            "bash",
            "-ceu",
            'args="register-model-candidate,--tenant-id,$3,--artifact-uri,$4,--metadata-uri,$5,'
            '--pipeline-run,$6"; set -- "$0" "$1" "$2" "$args"; ' + _EXECUTE,
        ],
        args=[project, region, job, tenant_id, artifact_uri, metadata_uri, dsl.PIPELINE_JOB_NAME_PLACEHOLDER],
    )


@dsl.container_component
def reembed_corpus(
    project: str,
    region: str,
    job: str,
    tenant_id: str,
    encoder_name: str,
    encoder_version: str,
    embed_url: str,
) -> dsl.ContainerSpec:
    """``reembed-corpus``: stage the corpus under the new encoder (no effect on diagnoses)."""
    return dsl.ContainerSpec(
        image=GCLOUD_IMAGE,
        command=[
            "bash",
            "-ceu",
            'args="reembed-corpus,--tenant-id,$3,--encoder-name,$4,--encoder-version,$5,'
            '--embed-url,$6"; set -- "$0" "$1" "$2" "$args"; ' + _EXECUTE,
        ],
        args=[project, region, job, tenant_id, encoder_name, encoder_version, embed_url],
    )


@dsl.container_component
def finetune_and_export(
    corpus_bucket: str,
    tenant_id: str,
    export_date: str,
    base_model_uri: str,
    base_version: str,
    artifact_uri: dsl.OutputPath(str),  # type: ignore[valid-type]
    metadata_uri: dsl.OutputPath(str),  # type: ignore[valid-type]
) -> dsl.ContainerSpec:
    """ml/ondevice: mirror, fine-tune, quantise + evaluate, upload the candidate."""
    script = r"""
corpus="$1"; tenant="$2"; day="$3"; base_uri="$4"; base_version="$5"; out_artifact="$6"; out_meta="$7"
export_uri="gs://${corpus}/training/${tenant}/${day}/manifest.csv"
mkdir -p data/mirror runs/base
gcloud storage cp "${export_uri}" data/export.csv
gcloud storage rsync --recursive "gs://${corpus}" "data/mirror/${corpus}" --exclude="^(training|models|eval)/"
gcloud storage cp "${base_uri}" runs/base/model.keras
uv run --frozen python finetune.py --training-export data/export.csv --training-export-uri "${export_uri}" \
  --images-dir data/mirror --base runs/base/model.keras --base-version "${base_version}" --out runs/candidate
version="$(cat runs/candidate/next_version.txt)"
uv run --frozen python export.py --keras runs/candidate/model.keras --out runs/candidate/export \
  --model-version "${version}" --source public+field --training-manifest-uri "${export_uri}"
dest="gs://${corpus}/models/on-device/${version}"
gcloud storage cp runs/candidate/export/crop_quality_v1.tflite "${dest}/model.tflite"
gcloud storage cp runs/candidate/export/metadata.json "${dest}/metadata.json"
gcloud storage cp runs/candidate/model.keras "${dest}/model.keras"
mkdir -p "$(dirname "${out_artifact}")" "$(dirname "${out_meta}")"
printf '%s' "${dest}/model.tflite" > "${out_artifact}"
printf '%s' "${dest}/metadata.json" > "${out_meta}"
"""
    return dsl.ContainerSpec(
        image=ONDEVICE_IMAGE,
        command=["bash", "-ceu", script, "finetune"],
        args=[
            corpus_bucket,
            tenant_id,
            export_date,
            base_model_uri,
            base_version,
            artifact_uri,
            metadata_uri,
        ],
    )


@dsl.pipeline(
    name="ondevice-monthly-finetune",
    description="DX-012: export approved field images, fine-tune the on-device model, register a "
    "candidate; an agronomist / owner approves it in the console before any app downloads it.",
)
def ondevice_monthly_finetune(
    project: str,
    region: str,
    tenant_id: str,
    corpus_bucket: str,
    export_date: str,
    base_model_uri: str,
    base_version: str,
) -> None:
    export = run_api_job(
        project=project,
        region=region,
        job="export-training-set",
        command="export-training-set",
        tenant_id=tenant_id,
    ).set_display_name("export-training-set")
    candidate = (
        finetune_and_export(
            corpus_bucket=corpus_bucket,
            tenant_id=tenant_id,
            export_date=export_date,
            base_model_uri=base_model_uri,
            base_version=base_version,
        )
        .after(export)
        .set_display_name("finetune-and-export")
        .set_cpu_limit("8")
        .set_memory_limit("32G")
    )
    register_candidate(
        project=project,
        region=region,
        job="export-training-set",  # same image / SA; the command is overridden
        tenant_id=tenant_id,
        artifact_uri=candidate.outputs["artifact_uri"],
        metadata_uri=candidate.outputs["metadata_uri"],
    ).set_display_name("register-model-candidate (approval gate in the API)")


@dsl.pipeline(
    name="encoder-reembed",
    description="DX-012: stage the corpus under a new encoder and evaluate it; a human retunes "
    "thresholds, moves the API pin and runs activate-encoder.",
)
def encoder_reembed(
    project: str,
    region: str,
    tenant_id: str,
    encoder_name: str,
    encoder_version: str,
    embed_url: str,
) -> None:
    staged = reembed_corpus(
        project=project,
        region=region,
        job="export-training-set",
        tenant_id=tenant_id,
        encoder_name=encoder_name,
        encoder_version=encoder_version,
        embed_url=embed_url,
    ).set_display_name("reembed-corpus (staging only)")
    run_api_job(
        project=project,
        region=region,
        job="diagnosis-evaluate",
        command="diagnosis-evaluate",
        tenant_id=tenant_id,
    ).after(staged).set_display_name("diagnosis-evaluate (held-out set, current pin)")


PIPELINES = {
    "ondevice_monthly_finetune.yaml": ondevice_monthly_finetune,
    "encoder_reembed.yaml": encoder_reembed,
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "compiled")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for name, pipeline in PIPELINES.items():
        compiler.Compiler().compile(pipeline_func=pipeline, package_path=str(args.out / name))
        print(f"compiled {args.out / name}")  # noqa: T201


if __name__ == "__main__":
    main()
