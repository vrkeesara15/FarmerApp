"""``DiagnosisServices`` — the pluggable parts of the pipeline, built once per process.

``app.state.diagnosis`` in the API, a cached instance in the worker; tests pass their own
(``FakeEncoder``, a scripted LLM client, a ``RecordingPublisher``).
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

from farmerapp.diagnosis.encoder import ImageEncoder, build_encoder
from farmerapp.diagnosis.llm import (
    DisabledLlmClient,
    FakeLlmDiagnosisClient,
    LazyClaudeClient,
    LlmDiagnosisClient,
)
from farmerapp.payments.publisher import Publisher, PubSubRestPublisher
from farmerapp.settings import Settings, get_settings
from farmerapp.uploads.blobstore import BlobStore, build_blob_store


@dataclass
class DiagnosisServices:
    settings: Settings
    encoder: ImageEncoder
    llm: LlmDiagnosisClient
    blobs: BlobStore
    publisher: Publisher | None = None  # None = run the pipeline inline (local / dev)


def build_llm(settings: Settings) -> LlmDiagnosisClient:
    if settings.diagnosis_llm == "fake":
        return FakeLlmDiagnosisClient()
    if settings.diagnosis_llm == "off":
        return DisabledLlmClient()
    return LazyClaudeClient(
        model=settings.diagnosis_llm_model,
        max_tokens=settings.diagnosis_llm_max_tokens,
        effort=settings.diagnosis_llm_effort,
    )


def build_diagnosis_services(
    settings: Settings, *, blobs: BlobStore | None = None
) -> DiagnosisServices:
    publisher: Publisher | None = None
    if settings.diagnosis_delivery == "pubsub":  # pragma: no cover - needs the emulator / GCP
        from farmerapp.gcp import GoogleAccessToken

        publisher = PubSubRestPublisher(
            base_url=settings.pubsub_emulator_host or "https://pubsub.googleapis.com",
            project=settings.gcp_project,
            token_provider=None if settings.pubsub_emulator_host else GoogleAccessToken(),
        )
    return DiagnosisServices(
        settings=settings,
        encoder=build_encoder(settings),
        llm=build_llm(settings),
        blobs=blobs or build_blob_store(settings),
        publisher=publisher,
    )


@lru_cache(maxsize=1)
def worker_services() -> DiagnosisServices:
    """The worker's services (one encoder / LLM client per process)."""
    return build_diagnosis_services(get_settings())


__all__ = ["DiagnosisServices", "build_diagnosis_services", "build_llm", "worker_services"]
