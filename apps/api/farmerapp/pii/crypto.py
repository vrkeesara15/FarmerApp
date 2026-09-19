"""Envelope encryption of PII fields (SEC-026).

Layout of a ciphertext (``bytea``): ``0x01 | key_version (2 bytes, big endian) | nonce (12) |
AES-256-GCM(ciphertext + 16-byte tag)``. The associated data is
``farmerapp:pii:v1|<tenant_id>|<table>|<column>``: decrypting with another tenant's key, or a
value copied into another tenant, table or column, fails authentication (``PiiDecryptError``).

Data keys (DEK): 32 random bytes per tenant and ``key_version``, stored only **wrapped** in
``tenant_data_key``; the key-encryption key (KEK) never leaves its backend:

* ``CloudKmsKeyWrapper`` — Cloud KMS ``encrypt`` / ``decrypt`` over REST with associated data
  ``farmerapp:dek|<tenant_id>|v<version>`` (key ring in asia-south1, NF-011). Required in prd
  (``Settings._prd_guard_rails``).
* ``LocalKeyWrapper`` — AES-256-GCM with ``PII_LOCAL_KEK`` (or the built-in dev key): local,
  test and dev only.

Unwrapped DEKs are cached per process (``FieldCipher.keys``); encrypt / decrypt are then
synchronous (microseconds), so ORM attribute access stays synchronous.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import re
import threading
import uuid
from typing import Protocol
from urllib.parse import quote

import httpx
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from farmerapp.gcp import TokenProvider
from farmerapp.settings import DEV_PII_LOCAL_KEK, Settings, get_settings

FORMAT_V1 = 0x01
NONCE_BYTES = 12
KEY_BYTES = 32
_INDIAN_MOBILE = re.compile(r"^\+91[6-9]\d{9}$")


class PiiError(RuntimeError):
    """Base class of PII encryption errors."""


class PiiKeyNotLoadedError(PiiError):
    """No data key of that tenant / version is loaded in this process (tenant not bound)."""


class PiiDecryptError(PiiError):
    """Authentication failed: wrong tenant, table, column or key, or tampered bytes."""


# --------------------------------------------------------------------------- phone hash
def normalise_phone(value: str) -> str:
    """Accept ``9876543210`` / ``+91 98765 43210`` / ``+919876543210``; return E.164."""
    digits = re.sub(r"[\s\-()]", "", value)
    if re.fullmatch(r"[6-9]\d{9}", digits):
        digits = "+91" + digits
    elif re.fullmatch(r"0[6-9]\d{9}", digits):
        digits = "+91" + digits[1:]
    elif re.fullmatch(r"91[6-9]\d{9}", digits):
        digits = "+" + digits
    if not _INDIAN_MOBILE.fullmatch(digits):
        raise ValueError("must be an Indian mobile number (+91 and 10 digits starting 6-9)")
    return digits


def _canonical(phone: str) -> str:
    try:
        return normalise_phone(phone)
    except ValueError:
        return re.sub(r"[\s\-()]", "", phone)  # legacy / foreign value: hash as stored


def phone_hash(phone: str, *, pepper: str | None = None) -> str:
    """Searchable hash: hex HMAC-SHA256(pepper, normalised E.164). Same number, same hash in
    every tenant (login resolves the tenant from it); uniqueness is per tenant."""
    key = (pepper if pepper is not None else get_settings().pii_hash_pepper).encode()
    return hmac.new(key, _canonical(phone).encode(), hashlib.sha256).hexdigest()


# --------------------------------------------------------------------------- KEK
def dek_aad(tenant_id: uuid.UUID, version: int) -> bytes:
    return f"farmerapp:dek|{tenant_id}|v{version}".encode()


def field_aad(tenant_id: uuid.UUID, table: str, column: str) -> bytes:
    return f"farmerapp:pii:v1|{tenant_id}|{table}|{column}".encode()


class KeyWrapper(Protocol):
    backend: str
    name: str

    async def wrap(self, dek: bytes, aad: bytes) -> bytes: ...

    async def unwrap(self, wrapped: bytes, aad: bytes) -> bytes: ...


class LocalKeyWrapper:
    """AES-256-GCM with a key from settings (dev / test only; refused in prd)."""

    backend = "local"

    def __init__(self, kek: bytes, *, name: str = "local") -> None:
        if len(kek) != KEY_BYTES:
            raise ValueError("the local key-encryption key must be 32 bytes")
        self._aead = AESGCM(kek)
        self.name = name

    async def wrap(self, dek: bytes, aad: bytes) -> bytes:
        nonce = os.urandom(NONCE_BYTES)
        return nonce + self._aead.encrypt(nonce, dek, aad)

    async def unwrap(self, wrapped: bytes, aad: bytes) -> bytes:
        try:
            return self._aead.decrypt(wrapped[:NONCE_BYTES], wrapped[NONCE_BYTES:], aad)
        except InvalidTag as exc:
            raise PiiDecryptError("data key does not unwrap with this KEK") from exc


class CloudKmsKeyWrapper:
    """Cloud KMS symmetric key (``projects/…/cryptoKeys/…``) over the REST API."""

    backend = "kms"

    def __init__(
        self,
        key_name: str,
        token: TokenProvider,
        *,
        client: httpx.AsyncClient | None = None,
        base_url: str = "https://cloudkms.googleapis.com",
    ) -> None:
        self.name = key_name
        self._token = token
        self._client = client
        self._base = base_url.rstrip("/")

    async def _call(self, verb: str, body: dict[str, str]) -> dict[str, str]:
        url = f"{self._base}/v1/{quote(self.name, safe='/')}:{verb}"
        headers = {"Authorization": f"Bearer {await self._token()}"}
        if self._client is not None:
            resp = await self._client.post(url, json=body, headers=headers)
        else:  # pragma: no cover - real network
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(url, json=body, headers=headers)
        resp.raise_for_status()
        data: dict[str, str] = resp.json()
        return data

    async def wrap(self, dek: bytes, aad: bytes) -> bytes:
        out = await self._call(
            "encrypt",
            {
                "plaintext": base64.b64encode(dek).decode(),
                "additionalAuthenticatedData": base64.b64encode(aad).decode(),
            },
        )
        return base64.b64decode(out["ciphertext"])

    async def unwrap(self, wrapped: bytes, aad: bytes) -> bytes:
        out = await self._call(
            "decrypt",
            {
                "ciphertext": base64.b64encode(wrapped).decode(),
                "additionalAuthenticatedData": base64.b64encode(aad).decode(),
            },
        )
        return base64.b64decode(out["plaintext"])


def build_wrapper(settings: Settings) -> KeyWrapper:
    if settings.pii_kek_backend == "kms":
        if not settings.pii_kms_key_name:
            raise ValueError("PII_KEK_BACKEND=kms needs PII_KMS_KEY_NAME")
        from farmerapp.gcp import GoogleAccessToken

        return CloudKmsKeyWrapper(settings.pii_kms_key_name, GoogleAccessToken())
    if settings.app_env == "prd":
        raise ValueError("a local PII key-encryption key is refused in prd")
    raw = settings.pii_local_kek or DEV_PII_LOCAL_KEK
    return LocalKeyWrapper(base64.b64decode(raw))


# --------------------------------------------------------------------------- cipher
class FieldCipher:
    """Per-tenant DEK cache + AES-256-GCM of field values."""

    def __init__(self, wrapper: KeyWrapper) -> None:
        self.wrapper = wrapper
        self._keys: dict[uuid.UUID, dict[int, AESGCM]] = {}
        self._current: dict[uuid.UUID, int] = {}
        self._lock = threading.Lock()

    # keys ---------------------------------------------------------------
    def has_tenant(self, tenant_id: uuid.UUID) -> bool:
        return tenant_id in self._current

    def load_key(self, tenant_id: uuid.UUID, version: int, dek: bytes) -> None:
        with self._lock:
            self._keys.setdefault(tenant_id, {})[version] = AESGCM(dek)
            if version >= self._current.get(tenant_id, 0):
                self._current[tenant_id] = version

    def forget(self, tenant_id: uuid.UUID) -> None:
        with self._lock:
            self._keys.pop(tenant_id, None)
            self._current.pop(tenant_id, None)

    def _key(self, tenant_id: uuid.UUID, version: int) -> AESGCM:
        try:
            return self._keys[tenant_id][version]
        except KeyError as exc:
            raise PiiKeyNotLoadedError(
                f"no data key v{version} loaded for tenant {tenant_id}; bind the tenant first"
            ) from exc

    # values ---------------------------------------------------------------
    def encrypt(self, tenant_id: uuid.UUID, table: str, column: str, plaintext: str) -> bytes:
        version = self._current.get(tenant_id)
        if version is None:
            raise PiiKeyNotLoadedError(f"no data key loaded for tenant {tenant_id}")
        nonce = os.urandom(NONCE_BYTES)
        body = self._key(tenant_id, version).encrypt(
            nonce, plaintext.encode(), field_aad(tenant_id, table, column)
        )
        return bytes([FORMAT_V1]) + version.to_bytes(2, "big") + nonce + body

    def decrypt(self, tenant_id: uuid.UUID, table: str, column: str, blob: bytes) -> str:
        if len(blob) < 3 + NONCE_BYTES + 16 or blob[0] != FORMAT_V1:
            raise PiiDecryptError("not a PII ciphertext")
        version = int.from_bytes(blob[1:3], "big")
        nonce, body = blob[3 : 3 + NONCE_BYTES], blob[3 + NONCE_BYTES :]
        try:
            plain = self._key(tenant_id, version).decrypt(
                nonce, body, field_aad(tenant_id, table, column)
            )
        except InvalidTag as exc:
            raise PiiDecryptError(
                f"ciphertext does not authenticate for tenant {tenant_id} {table}.{column}"
            ) from exc
        return plain.decode()


_cipher: FieldCipher | None = None


def get_cipher() -> FieldCipher:
    global _cipher
    if _cipher is None:
        _cipher = FieldCipher(build_wrapper(get_settings()))
    return _cipher


def set_cipher(cipher: FieldCipher | None) -> None:
    """Replace the process cipher (tests; ``None`` rebuilds from settings on next use)."""
    global _cipher
    _cipher = cipher


__all__ = [
    "CloudKmsKeyWrapper",
    "FieldCipher",
    "KeyWrapper",
    "LocalKeyWrapper",
    "PiiDecryptError",
    "PiiError",
    "PiiKeyNotLoadedError",
    "build_wrapper",
    "dek_aad",
    "field_aad",
    "get_cipher",
    "normalise_phone",
    "phone_hash",
    "set_cipher",
]
