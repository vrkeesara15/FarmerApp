"""SEC-026 PII field-level encryption (Cloud KMS envelope) with a searchable phone hash.

* ``crypto`` — ``FieldCipher``: AES-256-GCM per value with a **data key per tenant**
  (``tenant_data_key``, wrapped by the key-encryption key: Cloud KMS in GCP, a local AES key
  in dev / test only) and associated data ``tenant id | table | column``, so a ciphertext
  moved to another tenant, table or column does not decrypt. ``phone_hash``: HMAC-SHA256 of
  the normalised E.164 number with a pepper from Secret Manager.
* ``keys`` — loads / creates the tenant's data key when a tenant is bound (``set_tenant``).
* ``fields`` — ``EncryptedField``: the ``phone`` / ``landmark`` attributes of ``user`` and
  ``farmer`` read the ciphertext (falling back to the legacy plain column during the
  transition) and write ciphertext + hash at flush time.
* ``lookup`` — ``phone_match``: every lookup by phone goes through the hash.
* ``backfill`` — the idempotent, resumable job that encrypts rows written before Alembic 0025.
"""
