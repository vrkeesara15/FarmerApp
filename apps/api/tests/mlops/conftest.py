"""M7 diagnosis ML-ops fixtures: the SMALL world with its paddy corpus, diagnosis services
with the fake encoder and a scriptable LLM, and the app's local blob store."""

from __future__ import annotations

import hashlib

import pytest
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.models import PestOrDisease
from farmerapp.diagnosis.images import synthetic_leaf
from farmerapp.diagnosis.models import CorpusImage, CorpusProblem
from farmerapp.uploads.blobstore import BlobStore, parse_uri
from tests.authz.conftest import Bearer, World, bearer, step_up  # noqa: F401
from tests.authz.conftest import world as world  # fixture re-exported
from tests.diagnosis.conftest import ScriptedLlm, llm, services  # noqa: F401


@pytest.fixture
def blobs(app: FastAPI) -> BlobStore:
    store: BlobStore = app.state.blobs
    return store


async def write_corpus_blobs(session: AsyncSession, blobs: BlobStore) -> int:
    """Put the seeded (synthetic) corpus images where their ``blob_uri`` points (the test
    seed does not write blobs): the bytes are recovered from the problem code and sha256."""
    rows = (
        await session.execute(
            select(CorpusImage, PestOrDisease.code)
            .join(CorpusProblem, CorpusProblem.id == CorpusImage.problem_id)
            .join(PestOrDisease, PestOrDisease.id == CorpusProblem.pest_or_disease_id)
        )
    ).tuples()
    written = 0
    for image, code in rows:
        for variant in range(16):
            data = synthetic_leaf(code, variant)
            if hashlib.sha256(data).hexdigest() == image.sha256:
                _, key = parse_uri(image.blob_uri)
                await blobs.put(key, data, content_type="image/jpeg")
                written += 1
                break
    return written
