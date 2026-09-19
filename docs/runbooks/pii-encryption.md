# PII field encryption (SEC-026): setup, rollout, backfill, contract, rotation

Owner: platform-lead. Severity when it goes wrong: sev2 (reads of encrypted fields fail with
`PiiKeyNotLoadedError` / `PiiDecryptError`, logged as `pii_data_key_unavailable` or 500s).

## What is encrypted

| Table | Logical field | At rest | Lookup |
|---|---|---|---|
| `user` | `phone` | `phone_enc` (AES-256-GCM) | `phone_hash` (HMAC-SHA256, unique per tenant; login looks it up across tenants through `auth_find_user_by_phone_hash`) |
| `farmer` | `phone` | `phone_enc` | `phone_hash` (unique per tenant); `phone_last4` stays for the directory / masks |
| `farmer` | `landmark` | `landmark_enc` | none |

Each tenant has its own data key (`tenant_data_key`, wrapped by the key-encryption key);
associated data = `tenant id | table | column`. Logs, audit rows (`+91******3210`,
`[encrypted]`) and marts keep masking as before; the API returns plaintext to the roles that
could see it before (agronomists still get a masked phone and no landmark).

## One-time Google Cloud setup (human gate)

1. Key ring and key in **asia-south1** (NF-011), e.g. `farmerapp-<env>` / `pii`, purpose
   `ENCRYPT_DECRYPT`, protection level `SOFTWARE` (or `HSM`), rotation 90 days. Terraform:
   `google_kms_key_ring` + `google_kms_crypto_key` in the env stack (follow-up module).
2. `roles/cloudkms.cryptoKeyEncrypterDecrypter` on that key for the **api**, **worker** and
   **jobs** service accounts (nobody else; auditors read KMS audit logs, SEC-017).
3. Secret Manager secret `pii-hash-pepper` (>= 32 random chars, created by a human, SEC-013),
   injected as `PII_HASH_PEPPER` into api / worker / jobs. **Never rotate it casually**: every
   `phone_hash` depends on it (a change needs a re-hash job).
4. Env: `PII_KEK_BACKEND=kms`, `PII_KMS_KEY_NAME=projects/<p>/locations/asia-south1/keyRings/
   farmerapp-<env>/cryptoKeys/pii`, `PII_LOCAL_KEK` unset. The API refuses to start in prd
   otherwise (`Settings._prd_guard_rails`).

## Rollout: expand -> migrate -> contract (SPEC 10.2)

1. **Expand** (Alembic 0025, automatic with the release): new nullable columns, hash indexes,
   `tenant_data_key`, the hash login function. The previous release keeps working.
   The new code writes ciphertext + hash and leaves the plain columns NULL. For a rollback-safe
   first deploy set `PII_PLAINTEXT_WRITES=true` (also writes the plain columns), then turn it
   off once the release is stable.
2. **Migrate** (job, per tenant, repeatable): encrypt the rows written before 0025.

   ```
   python -m farmerapp.jobs pii-backfill --tenant <id|slug> [--batch-size 500]
   ```

   Batches of 500 by id, one transaction each (resumable: re-run after an interruption);
   idempotent (a second run reports `changed=0 remaining=0`). `conflicts` > 0 means two legacy
   rows of one tenant hold the same normalised phone: resolve them through the VA-F02 flags,
   then re-run. One `pii.backfill` audit row per tenant and run.
3. Verify per tenant: `remaining=0 conflicts=0`; spot-check the console directory, login and
   a farmer registration. Then, with `PII_PLAINTEXT_WRITES=false` everywhere:

   ```
   python -m farmerapp.jobs pii-backfill --tenant <id|slug> --clear-plaintext
   ```

   (refused while `PII_PLAINTEXT_WRITES` is on). The plain columns are now NULL.
4. **Contract** (manual, a release of its own, at least one release later): the code that
   release ships must no longer map `phone_plain` / `landmark_plain` nor fall back to them in
   `farmerapp/pii/lookup.py` and `fields.py`. Take a Cloud SQL backup / note the PITR point,
   move `apps/api/alembic/manual/pii_contract.py` to `alembic/versions/0NNN_pii_contract.py`
   (next number, `down_revision` = current head) and deploy. It refuses to run while any row
   still has a plain value or lacks a ciphertext / hash.

## Rollback

- Before contract: redeploy the previous release. Rows written by the new release have no
  plain phone unless `PII_PLAINTEXT_WRITES` was on — restore them first:
  `pii-backfill --tenant … --restore-plaintext` (decrypts into the empty plain columns).
  Alembic 0025's downgrade refuses while any row lacks a plain phone.
- After contract: restore from backup (the contract downgrade only re-creates empty columns;
  `--restore-plaintext` refills them from the ciphertext).

## Key rotation

- KEK (Cloud KMS): automatic rotation creates a new key version; old wrapped data keys stay
  decryptable (KMS keeps old versions enabled). Nothing to do in the app.
- Data keys: a rotation is a new `tenant_data_key` row with `key_version + 1` (append-only
  table); new values use the newest version, old values carry their version in the ciphertext
  header. A re-encryption job for old values is a follow-up (not needed for the pilot).

## Detection and verification

- `pii_data_key_unavailable` (WARNING) with the tenant id: KMS unreachable or permission
  missing — check the service account role and the key state in Cloud KMS.
- `pii_backfill_conflict` (WARNING): duplicate legacy phones (see step 2).
- `SELECT count(*) FROM farmer WHERE phone_enc IS NULL` per tenant as the owner role: 0 after
  the backfill.
