"""NF-011 egress register: every outbound call the backend makes, and what it carries.

Data residency is two claims. The first — *personal data is stored and processed in
asia-south1 / asia-south2* — is a Terraform property, checked by
``tests/deploy/test_residency.py`` against the real ``.tf`` files. The second — *nothing
personal leaves those regions* — is a property of this code, and this module is where it is
written down: one :class:`Egress` entry per destination the process can open a socket to,
naming the module, what the payload carries, and whether the destination sits inside an
Indian region.

The rule the test enforces: **no destination outside an Indian region may be marked as
carrying personal data.** A new outbound call must add an entry (the test greps
``farmerapp/`` for HTTP clients and fails on a module that is not registered), and marking a
foreign destination ``personal_data=True`` fails the build — which is the point: that is a
decision for a DPIA, not for a pull request.

Three destinations are outside an Indian region. Two are live:

``anthropic``  the DX-004 diagnosis fallback and the VA-004 flag summaries. Carries the
               photo (re-encoded, EXIF and GPS stripped) plus crop, district, season, crop
               stage and candidate problem ids — never a name, phone, id or coordinate.
               Enforced by the shared guard ``farmerapp.pii.llm_guard`` and its tests.
``open_meteo`` the FM-008 forecast. Carries the latitude and longitude of the farm's
               0.1-degree grid cell (about 11 km) rounded to one decimal, and nothing else:
               no farm polygon, no farmer, no id, no key.

The third, ``google_roads`` (VV-006 track snapping), *would* carry an officer's GPS track and
is therefore **off in every environment** (``ROAD_SNAPPER=off``). It is the one entry allowed
to declare ``personal_data=True`` outside India, and only because it carries a ``review`` and
an ``off_switch``; the test refuses any foreign personal-data egress without both.

Everything else either stays in the project's own region (Cloud SQL, GCS, KMS, Pub/Sub, the
embed service) or goes to a contracted Indian provider (the OTP SMS / WhatsApp gateway,
Razorpay). Those may carry personal data; the residency obligation is met by the contract and
by the provider's own Indian hosting, recorded in ``docs/dpdp.md``.
"""

from __future__ import annotations

from dataclasses import dataclass

__all__ = ["EGRESS", "Egress", "foreign_destinations", "registered_modules"]


@dataclass(frozen=True)
class Egress:
    """One outbound destination."""

    #: Short key used in docs and logs.
    name: str
    #: The ``farmerapp`` module that opens the connection.
    module: str
    #: Why the call is made.
    purpose: str
    #: What the request body / query carries.
    carries: str
    #: True when the endpoint is served from asia-south1 / asia-south2 or another Indian
    #: region (a contracted Indian provider counts; the contract is recorded in docs/dpdp.md).
    indian_region: bool
    #: True when the payload can contain personal data of a data principal.
    personal_data: bool
    #: How the claim above is kept true.
    control: str
    #: Set only for a foreign destination that *can* carry personal data: the review that
    #: allows it, and the switch that keeps it off until someone turns it on deliberately.
    #: ``tests/deploy/test_residency.py`` refuses any other foreign personal-data egress.
    review: str | None = None
    #: Settings field (and its off value) that disables the call. Required with ``review``.
    off_switch: tuple[str, str] | None = None


EGRESS: tuple[Egress, ...] = (
    Egress(
        name="anthropic",
        module="farmerapp.diagnosis.llm",
        purpose="DX-004 diagnosis fallback when the corpus is not confident",
        carries="EXIF-stripped photo; crop, district, season, crop stage, candidate problem ids",
        indian_region=False,
        personal_data=False,
        control="farmerapp.pii.llm_guard.guard_prompt + images.strip_for_llm (SEC-027)",
    ),
    Egress(
        name="anthropic_flag_summary",
        module="farmerapp.flags.review_agent",
        purpose="VA-004 three-line review summary of one validation flag",
        carries="the scrubbed evidence bundle: rule id, severity, record ids, masked metrics",
        indian_region=False,
        personal_data=False,
        control="farmerapp.pii.llm_guard.scrub + guard_prompt (SEC-027)",
    ),
    Egress(
        name="open_meteo",
        module="farmerapp.advisory.weather",
        purpose="FM-008 seven-day forecast and spray windows",
        carries="latitude / longitude of the 0.1-degree grid cell, rounded to one decimal",
        indian_region=False,
        personal_data=False,
        control="grid rounding in WeatherProvider.params; the apps never call the provider",
    ),
    Egress(
        name="google_roads",
        module="farmerapp.duty.roads",
        purpose="VV-006 snap an officer's duty track to roads before measuring km",
        carries="the officer's GPS track (lat/lon, time) in chunks of 100 points",
        indian_region=False,
        personal_data=True,
        control="off by default; falls back to the in-process haversine snapper on any error",
        review=(
            "docs/dpdp.md 'Cross-border processing': an officer's track is employee personal "
            "data under a legitimate-use basis; sending it to the Google Roads API needs a "
            "recorded DPIA and a DPA before ROAD_SNAPPER is set to 'google' in any "
            "environment. Nothing enables it today."
        ),
        off_switch=("road_snapper", "off"),
    ),
    Egress(
        name="otp_sms",
        module="farmerapp.auth.providers",
        purpose="FA-001 OTP delivery by SMS and WhatsApp",
        carries="the recipient phone number and the six-digit code",
        indian_region=True,
        personal_data=True,
        control="Indian gateway (SMS_PROVIDER_URL from Secret Manager); SEC-021 send controls",
    ),
    Egress(
        name="razorpay",
        module="farmerapp.payments.providers",
        purpose="FA-021 UPI collect / QR and settlement reconciliation",
        carries="order id, amount in paise, the payer's phone when the farmer supplies one",
        indian_region=True,
        personal_data=True,
        control="Razorpay is an RBI-regulated Indian PA; HMAC-verified webhooks (SEC-023)",
    ),
    Egress(
        name="payments_webhook_publisher",
        module="farmerapp.payments.publisher",
        purpose="local / dev replay of a payment webhook to the API",
        carries="the provider's webhook body",
        indian_region=True,
        personal_data=True,
        control="same project; never used in prd (PAYMENT_WEBHOOK_DELIVERY=pubsub)",
    ),
    Egress(
        name="gcs",
        module="farmerapp.uploads.blobstore",
        purpose="NF-003 photo upload / download through signed URLs",
        carries="photo bytes",
        indian_region=True,
        personal_data=True,
        control="buckets created with location = upper(var.region) (asia-south1)",
    ),
    Egress(
        name="cloud_kms",
        module="farmerapp.pii.crypto",
        purpose="SEC-026 wrap / unwrap the per-tenant data key",
        carries="the wrapped data key (never plaintext PII)",
        indian_region=True,
        personal_data=False,
        control="PII_KMS_KEY_NAME pinned to locations/asia-south1 (prd guard rail)",
    ),
    Egress(
        name="embed",
        module="farmerapp.diagnosis.encoder",
        purpose="DX-002 image embedding",
        carries="photo bytes",
        indian_region=True,
        personal_data=True,
        control="Cloud Run service in var.region, ingress internal (infra/envs/*/main.tf)",
    ),
    Egress(
        name="fcm",
        module="farmerapp.notifications.push",
        purpose="FA-007 push notifications",
        carries="the device token and an i18n key with ids — never message text with a name",
        indian_region=True,
        personal_data=True,
        control="Firebase project of the same GCP project; payload is keys + ids",
    ),
    Egress(
        name="play_integrity",
        module="farmerapp.integrity.verifier",
        purpose="SEC-024 decode the Play Integrity token",
        carries="the opaque integrity token issued by Play",
        indian_region=True,
        personal_data=False,
        control="Google API; the token carries no farmer data",
    ),
    Egress(
        name="metadata_server",
        module="farmerapp.gcp",
        purpose="the runtime service account's identity / access token",
        carries="nothing (link-local metadata endpoint)",
        indian_region=True,
        personal_data=False,
        control="169.254.169.254, inside the instance",
    ),
    Egress(
        name="email",
        module="farmerapp.exports.email",
        purpose="WC-013 scheduled report delivery",
        carries="a staff recipient address and the report attachment",
        indian_region=True,
        personal_data=True,
        control="EMAIL_PROVIDER defaults to 'log'; a provider needs a DPA before it is set",
    ),
)


def foreign_destinations() -> tuple[Egress, ...]:
    """Destinations outside an Indian region. Must never carry personal data."""
    return tuple(e for e in EGRESS if not e.indian_region)


def registered_modules() -> frozenset[str]:
    return frozenset(e.module for e in EGRESS)
