"""SEC-026 envelope encryption without a database: AES-256-GCM with associated data, the
local and Cloud KMS key wrappers, the searchable hash, and the prd guard."""

from __future__ import annotations

import base64
import json
import os
import uuid

import httpx
import pytest

from farmerapp.pii.crypto import (
    CloudKmsKeyWrapper,
    FieldCipher,
    LocalKeyWrapper,
    PiiDecryptError,
    PiiKeyNotLoadedError,
    build_wrapper,
    dek_aad,
    phone_hash,
)
from farmerapp.pii.fields import EncryptedField
from farmerapp.settings import Settings

T1, T2 = uuid.uuid4(), uuid.uuid4()


def _cipher() -> FieldCipher:
    cipher = FieldCipher(LocalKeyWrapper(os.urandom(32)))
    cipher.load_key(T1, 1, os.urandom(32))
    cipher.load_key(T2, 1, os.urandom(32))
    return cipher


def test_round_trip_and_random_nonce() -> None:
    cipher = _cipher()
    a = cipher.encrypt(T1, "farmer", "phone", "+919876543210")
    b = cipher.encrypt(T1, "farmer", "phone", "+919876543210")
    assert a != b and b"9876543210" not in a  # fresh nonce, no plaintext in the bytes
    assert a[0] == 1 and int.from_bytes(a[1:3], "big") == 1  # format v1, key version 1
    assert cipher.decrypt(T1, "farmer", "phone", a) == "+919876543210"
    empty = cipher.encrypt(T1, "farmer", "landmark", "")
    assert cipher.decrypt(T1, "farmer", "landmark", empty) == ""


@pytest.mark.parametrize(
    ("tenant", "table", "column"),
    [(T2, "farmer", "phone"), (T1, "user", "phone"), (T1, "farmer", "landmark")],
)
def test_wrong_tenant_table_or_column_does_not_decrypt(
    tenant: uuid.UUID, table: str, column: str
) -> None:
    cipher = _cipher()
    blob = cipher.encrypt(T1, "farmer", "phone", "+919876543210")
    with pytest.raises(PiiDecryptError):
        cipher.decrypt(tenant, table, column, blob)


def test_tampered_or_foreign_bytes_fail() -> None:
    cipher = _cipher()
    blob = bytearray(cipher.encrypt(T1, "user", "phone", "+919876543210"))
    blob[-1] ^= 0x01
    with pytest.raises(PiiDecryptError):
        cipher.decrypt(T1, "user", "phone", bytes(blob))
    with pytest.raises(PiiDecryptError):
        cipher.decrypt(T1, "user", "phone", b"\x02short")


def test_rotation_keeps_old_versions_readable() -> None:
    cipher = _cipher()
    old = cipher.encrypt(T1, "user", "phone", "+919876543210")
    cipher.load_key(T1, 2, os.urandom(32))
    new = cipher.encrypt(T1, "user", "phone", "+919876543210")
    assert int.from_bytes(new[1:3], "big") == 2
    assert cipher.decrypt(T1, "user", "phone", old) == cipher.decrypt(T1, "user", "phone", new)


def test_unknown_tenant_key_is_a_clear_error() -> None:
    cipher = _cipher()
    with pytest.raises(PiiKeyNotLoadedError):
        cipher.encrypt(uuid.uuid4(), "user", "phone", "+919876543210")
    blob = cipher.encrypt(T1, "user", "phone", "+919876543210")
    cipher.forget(T1)
    with pytest.raises(PiiKeyNotLoadedError):
        cipher.decrypt(T1, "user", "phone", blob)


def test_phone_hash_is_normalised_peppered_and_deterministic() -> None:
    pepper = "p" * 40
    assert phone_hash("+919876543210", pepper=pepper) == phone_hash("98765 43210", pepper=pepper)
    assert phone_hash("09876543210", pepper=pepper) == phone_hash("919876543210", pepper=pepper)
    assert phone_hash("+919876543210", pepper=pepper) != phone_hash(
        "+919876543210", pepper="q" * 40
    )
    assert len(phone_hash("+919876543210", pepper=pepper)) == 64


async def test_local_wrapper_binds_the_tenant() -> None:
    wrapper = LocalKeyWrapper(os.urandom(32))
    dek = os.urandom(32)
    wrapped = await wrapper.wrap(dek, dek_aad(T1, 1))
    assert await wrapper.unwrap(wrapped, dek_aad(T1, 1)) == dek
    with pytest.raises(PiiDecryptError):
        await wrapper.unwrap(wrapped, dek_aad(T2, 1))
    with pytest.raises(ValueError, match="32 bytes"):
        LocalKeyWrapper(b"short")


async def test_cloud_kms_wrapper_calls_encrypt_and_decrypt_with_aad() -> None:
    key_name = "projects/p/locations/asia-south1/keyRings/farmerapp/cryptoKeys/pii"
    seen: list[tuple[str, dict[str, str]]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        seen.append((request.url.path, body))
        assert request.headers["Authorization"] == "Bearer token-1"
        if request.url.path.endswith(":encrypt"):
            blob = body["additionalAuthenticatedData"] + "|" + body["plaintext"]
            return httpx.Response(
                200, json={"ciphertext": base64.b64encode(blob.encode()).decode()}
            )
        aad, _, plain = base64.b64decode(body["ciphertext"]).decode().partition("|")
        if aad != body["additionalAuthenticatedData"]:
            return httpx.Response(400, json={"error": {"status": "INVALID_ARGUMENT"}})
        return httpx.Response(200, json={"plaintext": plain})

    async def token() -> str:
        return "token-1"

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        wrapper = CloudKmsKeyWrapper(key_name, token, client=client)
        dek = os.urandom(32)
        wrapped = await wrapper.wrap(dek, dek_aad(T1, 1))
        assert await wrapper.unwrap(wrapped, dek_aad(T1, 1)) == dek
        with pytest.raises(httpx.HTTPStatusError):
            await wrapper.unwrap(wrapped, dek_aad(T2, 1))
    assert seen[0][0] == f"/v1/{key_name}:encrypt" and seen[1][0] == f"/v1/{key_name}:decrypt"
    assert wrapper.backend == "kms" and wrapper.name == key_name


def test_prd_refuses_a_local_key_encryption_key() -> None:
    """Belt and braces: even a Settings object built around validation cannot get a local KEK
    in prd (the validator itself is covered in tests/auth/test_settings.py)."""
    prd = Settings.model_construct(app_env="prd", pii_kek_backend="local", pii_local_kek=None)
    with pytest.raises(ValueError, match="refused in prd"):
        build_wrapper(prd)
    dev = Settings.model_construct(app_env="dev", pii_kek_backend="local", pii_local_kek=None)
    assert isinstance(build_wrapper(dev), LocalKeyWrapper)
    kms = Settings.model_construct(app_env="prd", pii_kek_backend="kms", pii_kms_key_name=None)
    with pytest.raises(ValueError, match="PII_KMS_KEY_NAME"):
        build_wrapper(kms)


def test_encrypted_attribute_cannot_be_compared_in_a_query() -> None:
    from farmerapp.farmers.models import Farmer

    field = Farmer.phone
    assert isinstance(field, EncryptedField)
    with pytest.raises(TypeError, match="phone_match"):
        _ = field == "+919876543210"
