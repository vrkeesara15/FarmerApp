"""``EncryptedField``: an ORM model attribute backed by a ciphertext column (SEC-026).

On a model::

    phone_plain: Mapped[str | None] = mapped_column("phone", String(16), nullable=True)
    phone_enc: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    phone_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    phone = EncryptedField(plain="phone_plain", enc="phone_enc", hash_attr="phone_hash")

* **read** ``obj.phone``: the value written in this unit of work, else the decrypted
  ``phone_enc`` (tenant key, associated data ``tenant | table | column``), else the legacy
  plain column (rows not yet backfilled: the expand -> migrate -> contract transition).
* **write** ``obj.phone = v``: the hash (and ``phone_last4`` where the model has it) is set
  at once, the ciphertext at flush (``encrypt_pending``, a ``before_flush`` listener: the row's
  ``tenant_id`` is known by then, whatever the constructor argument order). The plain column
  is cleared — or also written while ``PII_PLAINTEXT_WRITES`` is on (rollout safety).
* **query**: comparing the class attribute is a ``TypeError`` (it would silently compare a
  Python object); use ``farmerapp.pii.lookup.phone_match`` (hash) instead.

The FA-006 audit trail never sees ciphertext, hashes or plaintext: those columns are
redacted and ``audit_values`` supplies the masked logical value (phone -> ``+91******3210``,
other fields -> ``[encrypted]``).
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any, Self, overload

from sqlalchemy import event
from sqlalchemy.orm import Session

from farmerapp.pii.crypto import PiiKeyNotLoadedError, get_cipher, phone_hash

_PENDING = "_pii_pending"
_CHANGES = "_pii_changes"
_CACHE = "_pii_cache"
ENCRYPTED_MARK = "[encrypted]"


def _mask_phone(phone: str) -> str:
    prefix = "+91" if phone.startswith("+91") else ""
    rest = phone[len(prefix) :]
    if len(rest) <= 4:
        return prefix + "*" * len(rest)
    return prefix + "*" * (len(rest) - 4) + rest[-4:]


class EncryptedField[T: (str, str | None)]:
    """``EncryptedField[str]`` for a NOT NULL logical value, ``[str | None]`` otherwise."""

    def __init__(
        self,
        *,
        plain: str,
        enc: str,
        hash_attr: str | None = None,
        last4_attr: str | None = None,
        mask: Callable[[str], str] | None = None,
    ) -> None:
        self.plain = plain
        self.enc = enc
        self.hash_attr = hash_attr
        self.last4_attr = last4_attr
        self.mask = mask
        self.name = ""

    def __set_name__(self, owner: type, name: str) -> None:
        self.name = name

    # --------------------------------------------------------------- class access
    def __eq__(self, other: object) -> bool:
        raise TypeError(
            f"{self.name} is encrypted (SEC-026): query by farmerapp.pii.lookup.phone_match"
        )

    __hash__ = object.__hash__

    @property
    def column(self) -> str:
        return self.name  # the logical column name in the associated data

    def masked(self, value: str | None) -> str | None:
        if value is None:
            return None
        return self.mask(value) if self.mask is not None else ENCRYPTED_MARK

    # --------------------------------------------------------------- instance access
    @overload
    def __get__(self, obj: None, owner: type | None = None) -> Self: ...

    @overload
    def __get__(self, obj: object, owner: type | None = None) -> T: ...

    def __get__(self, obj: Any, owner: type | None = None) -> Any:
        if obj is None:
            return self
        pending: dict[str, str | None] = obj.__dict__.get(_PENDING) or {}
        if self.name in pending:
            return pending[self.name]
        blob = getattr(obj, self.enc)
        if blob is None:
            return getattr(obj, self.plain)
        blob = bytes(blob)
        cache: dict[str, tuple[bytes, str]] = obj.__dict__.setdefault(_CACHE, {})
        hit = cache.get(self.name)
        if hit is not None and hit[0] == blob:
            return hit[1]
        value = get_cipher().decrypt(obj.tenant_id, obj.__tablename__, self.column, blob)
        cache[self.name] = (blob, value)
        return value

    def __set__(self, obj: Any, value: T) -> None:
        try:
            current = self.__get__(obj)
        except PiiKeyNotLoadedError:
            current = None
        pending: dict[str, str | None] = obj.__dict__.get(_PENDING) or {}
        if value == current and self.name not in pending and getattr(obj, self.enc) is not None:
            return  # same value, already encrypted: no new ciphertext, no row change
        changes: dict[str, str | None] = obj.__dict__.setdefault(_CHANGES, {})
        if self.name not in changes:
            changes[self.name] = current
        obj.__dict__.setdefault(_PENDING, {})[self.name] = value
        obj.__dict__.get(_CACHE, {}).pop(self.name, None)
        if self.hash_attr is not None:
            setattr(obj, self.hash_attr, phone_hash(value) if value else None)
        if self.last4_attr is not None and value:
            setattr(obj, self.last4_attr, value[-4:])
        # Touch the ciphertext column so the row is dirty; the real value is set at flush.
        setattr(obj, self.enc, getattr(obj, self.enc))


def encrypted_fields(obj: object) -> list[EncryptedField[Any]]:
    return [v for v in vars(type(obj)).values() if isinstance(v, EncryptedField)]


def encrypt_object(obj: Any, *, plaintext_writes: bool) -> None:
    """Write the ciphertext (and the plain column when asked) of pending values."""
    pending: dict[str, str | None] | None = obj.__dict__.get(_PENDING)
    if not pending:
        return
    fields = {f.name: f for f in encrypted_fields(obj)}
    cipher = get_cipher()
    for name, value in list(pending.items()):
        field = fields[name]
        if value is None:
            setattr(obj, field.enc, None)
        else:
            blob = cipher.encrypt(obj.tenant_id, obj.__tablename__, field.column, value)
            setattr(obj, field.enc, blob)
            obj.__dict__.setdefault(_CACHE, {})[name] = (blob, value)
        setattr(obj, field.plain, value if plaintext_writes else None)
    obj.__dict__[_PENDING] = {}


def encrypt_pending(session: Session, _flush_context: Any, _instances: Any) -> None:
    """``before_flush``: encrypt every pending PII value of new and dirty rows."""
    from farmerapp.settings import get_settings

    plaintext_writes = get_settings().pii_plaintext_writes
    changed: list[Any] = session.info.setdefault(_CHANGES, [])
    for obj in [*session.new, *session.dirty]:
        if obj.__dict__.get(_CHANGES):
            changed.append(obj)
        if obj.__dict__.get(_PENDING):
            encrypt_object(obj, plaintext_writes=plaintext_writes)


def clear_changes(session: Session, _flush_context: Any) -> None:
    """``after_flush_postexec``: the audit trail has read the logical changes."""
    for obj in session.info.pop(_CHANGES, []):
        obj.__dict__.pop(_CHANGES, None)


def audit_values(obj: Any, *, created: bool) -> tuple[dict[str, Any], dict[str, Any]]:
    """Masked ``(before, after)`` of the object's PII fields for the FA-006 diff."""
    before: dict[str, Any] = {}
    after: dict[str, Any] = {}
    changes: dict[str, str | None] = obj.__dict__.get(_CHANGES) or {}
    for field in encrypted_fields(obj):
        if created:
            try:
                value = field.__get__(obj)
            except PiiKeyNotLoadedError:
                continue
            if value is not None:
                after[field.name] = field.masked(value)
            continue
        if field.name not in changes:
            continue
        old = changes[field.name]
        new = (obj.__dict__.get(_PENDING) or {}).get(field.name, None)
        if field.name not in (obj.__dict__.get(_PENDING) or {}):
            try:
                new = field.__get__(obj)
            except PiiKeyNotLoadedError:
                new = None
        if old == new:
            continue
        before[field.name] = field.masked(old)
        after[field.name] = field.masked(new)
    return before, after


def pii_columns(obj: object) -> set[str]:
    """Attribute keys the audit diff must never record raw (plain, cipher, hash)."""
    out: set[str] = set()
    for field in encrypted_fields(obj):
        out |= {field.plain, field.enc}
        if field.hash_attr is not None:
            out.add(field.hash_attr)
    return out


_installed = False


def install_listeners() -> None:
    global _installed
    if _installed:
        return
    event.listen(Session, "before_flush", encrypt_pending, insert=True)
    event.listen(Session, "after_flush_postexec", clear_changes)
    _installed = True


__all__ = [
    "ENCRYPTED_MARK",
    "EncryptedField",
    "audit_values",
    "encrypt_object",
    "encrypt_pending",
    "encrypted_fields",
    "install_listeners",
    "pii_columns",
]


# Phone fields show their last four digits in the audit trail, like the logs.
mask_phone = _mask_phone
