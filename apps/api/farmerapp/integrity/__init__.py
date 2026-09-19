"""Play Integrity server-side verification (SEC-024 server half, FA-028 / VA-E01 signal).

Contract with the apps (docs/prs/M5-mobile-security.md): sensitive requests carry
``X-Integrity-Action`` (comma list: ``login``, ``credit_sale``, ``payment_collection``,
``day_close``) and either ``X-Integrity-Token`` (a standard Play Integrity token whose
``requestHash`` binds it to this request) or ``X-Integrity-Status: unavailable``.

``farmerapp.integrity.verdict`` decides; ``farmerapp.integrity.verifier`` decodes tokens
(Google API or a fake); ``farmerapp.integrity.deps`` is the FastAPI dependency that records
the verdict on the request and in every audit row of the request. **Never blocks.**
"""
