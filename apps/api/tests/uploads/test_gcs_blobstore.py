"""SEC-016: ``GcsBlobStore`` V4 signed URLs (15 min) signed through IAM ``signBlob``.

A fake signer holds a local RSA key, so the test verifies the signature of the URL the way
Cloud Storage does: rebuild the canonical request from the URL, hash it, check the RSA
signature with the public key."""

from __future__ import annotations

import base64
import json
from datetime import UTC, datetime, timedelta
from urllib.parse import parse_qs, urlsplit

import httpx
import pytest
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa

from farmerapp.settings import Settings
from farmerapp.uploads.blobstore import (
    GCS_HOST,
    SIGNING_ALGORITHM,
    BlobNotFoundError,
    GcsBlobStore,
    IamBlobSigner,
    v4_string_to_sign,
)

SA = "farmerapp-api@farmerapp-dev.iam.gserviceaccount.com"
NOW = datetime(2026, 9, 19, 10, 30, 5, tzinfo=UTC)
URI = "gs://farmerapp-dev-photos/0f0e/visit_photo/ab cd+ef"


class RsaSigner:
    def __init__(self) -> None:
        self.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.signed: list[bytes] = []

    async def email(self) -> str:
        return SA

    async def sign(self, payload: bytes) -> bytes:
        self.signed.append(payload)
        return self.key.sign(payload, padding.PKCS1v15(), hashes.SHA256())


async def _token() -> str:
    return "access-token"


def _store(signer: RsaSigner, client: httpx.AsyncClient | None = None) -> GcsBlobStore:
    return GcsBlobStore(bucket="farmerapp-dev-photos", token=_token, signer=signer, client=client)


async def test_v4_signed_url_verifies_with_the_service_account_key() -> None:
    signer = RsaSigner()
    signed = await _store(signer).signed_url(URI, ttl=timedelta(minutes=15), now=NOW)
    assert signed.expires_at == NOW + timedelta(minutes=15)
    parts = urlsplit(signed.url)
    assert parts.scheme == "https" and parts.netloc == GCS_HOST
    assert parts.path == "/farmerapp-dev-photos/0f0e/visit_photo/ab%20cd%2Bef"
    query = parse_qs(parts.query)
    assert query["X-Goog-Algorithm"] == [SIGNING_ALGORITHM]
    assert query["X-Goog-Credential"] == [f"{SA}/20260919/auto/storage/goog4_request"]
    assert query["X-Goog-Date"] == ["20260919T103005Z"]
    assert query["X-Goog-Expires"] == ["900"]
    assert query["X-Goog-SignedHeaders"] == ["host"]
    signature = bytes.fromhex(query["X-Goog-Signature"][0])
    _, canonical_query, to_sign = v4_string_to_sign(
        bucket="farmerapp-dev-photos",
        key="0f0e/visit_photo/ab cd+ef",
        email=SA,
        now=NOW,
        ttl=timedelta(minutes=15),
    )
    assert parts.query.startswith(canonical_query + "&X-Goog-Signature=")
    assert signer.signed == [to_sign.encode()]
    assert to_sign.split("\n")[:3] == [
        SIGNING_ALGORITHM,
        "20260919T103005Z",
        "20260919/auto/storage/goog4_request",
    ]
    signer.key.public_key().verify(signature, to_sign.encode(), padding.PKCS1v15(), hashes.SHA256())


async def test_signed_url_ttl_is_capped_at_seven_days() -> None:
    signed = await _store(RsaSigner()).signed_url(URI, ttl=timedelta(days=30), now=NOW)
    assert "X-Goog-Expires=604800" in signed.url
    with pytest.raises(ValueError):
        await _store(RsaSigner()).signed_url("https://not-a-blob", ttl=timedelta(1), now=NOW)


async def test_iam_signer_calls_sign_blob_for_the_service_account() -> None:
    calls: list[tuple[str, dict[str, str], str]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        calls.append((request.url.path, body, request.headers["Authorization"]))
        signed = b"signed:" + base64.b64decode(body["payload"])
        return httpx.Response(
            200, json={"keyId": "k1", "signedBlob": base64.b64encode(signed).decode()}
        )

    async def email() -> str:
        return SA

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        signer = IamBlobSigner(_token, email_provider=email, client=client)
        assert await signer.sign(b"string-to-sign") == b"signed:string-to-sign"
        assert await signer.email() == SA
    path, body, auth = calls[0]
    assert path == f"/v1/projects/-/serviceAccounts/{SA}:signBlob"
    assert base64.b64decode(body["payload"]) == b"string-to-sign"
    assert auth == "Bearer access-token"
    with pytest.raises(RuntimeError):
        await IamBlobSigner(_token).email()


async def test_objects_go_through_the_json_api_with_a_bearer_token() -> None:
    stored: dict[str, bytes] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["Authorization"] == "Bearer access-token"
        if request.method == "POST":
            stored[request.url.params["name"]] = request.content
            return httpx.Response(200, json={"name": request.url.params["name"]})
        key = request.url.path.split("/o/", 1)[1]
        from urllib.parse import unquote

        name = unquote(key)
        if name not in stored:
            return httpx.Response(404)
        if request.url.params.get("alt") == "media":
            return httpx.Response(200, content=stored[name])
        return httpx.Response(200, json={"name": name})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        store = _store(RsaSigner(), client)
        uri = await store.put("t/visit_photo/abc", b"jpeg", content_type="image/jpeg")
        assert uri == "gs://farmerapp-dev-photos/t/visit_photo/abc"
        assert await store.get(uri) == b"jpeg" and await store.exists(uri)
        assert not await store.exists("gs://farmerapp-dev-photos/t/visit_photo/nope")
        assert not await store.exists("not a uri")
        with pytest.raises(BlobNotFoundError):
            await store.get("gs://farmerapp-dev-photos/t/visit_photo/nope")


def test_blob_store_setting_accepts_gcs() -> None:
    settings = Settings(blob_store="gcs", gcs_signing_service_account=SA)
    assert settings.blob_store == "gcs" and settings.gcs_signing_service_account == SA
