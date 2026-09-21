"""SEC-027: one guard for both LLM call sites.

These tests are the review gate. Adding a field to the DX-004 diagnosis prompt or a key to
the VA-004 evidence bundle fails here until the new field is listed in
``farmerapp.pii.llm_guard``, and a prompt that carries a name, a phone, an e-mail or a
coordinate pair is refused before it can reach a provider.
"""

from __future__ import annotations

import dataclasses
import uuid

import pytest

from farmerapp.diagnosis.images import strip_for_llm, synthetic_leaf, to_jpeg
from farmerapp.diagnosis.llm import (
    GUARD_SITE,
    LlmCandidate,
    LlmImage,
    LlmRequest,
    build_messages,
    guard_request,
    loggable_prompt,
)
from farmerapp.pii.llm_guard import (
    DIAGNOSIS_PROMPT_FIELDS,
    FLAG_BUNDLE_KEYS,
    PromptPiiError,
    assert_no_exif,
    findings,
    guard_prompt,
    is_pii_key,
    mask_text,
    scrub,
)

RECORD_ID = "2b0b7a2e-5a1b-4a7e-9d4e-2f8a6c1b3d5e"


# --------------------------------------------------------------------------- text findings
@pytest.mark.parametrize(
    ("text", "reason"),
    [
        ("call the farmer on +91 98765 43210", "phone-like digit run"),
        ("9876543210", "phone-like digit run"),
        ("write to ramesh.k@example.com", "email address"),
        ("aadhaar 1234 5678 9012", "Aadhaar-shaped number"),
        ("plot at 17.385044, 78.486671", "coordinate pair"),
    ],
)
def test_person_shaped_text_is_refused(text: str, reason: str) -> None:
    found = findings(text)
    assert any(reason in f for f in found), found
    with pytest.raises(PromptPiiError):
        guard_prompt(text, where="test")


@pytest.mark.parametrize(
    "text",
    [
        f"open record {RECORD_ID}",
        "closed 2026-09-18, 3 of 5 visits",
        "call ******3210 about the order",
        "Crop: cotton\nDistrict: Warangal\nSeason: kharif",
        "invoice total 45000 paise",
    ],
)
def test_clean_text_passes(text: str) -> None:
    assert findings(text) == []
    guard_prompt(text, where="test")


def test_record_ids_are_never_a_finding() -> None:
    """Ids are how the model is meant to refer to records: 32 hex digits are not a phone."""
    for _ in range(20):
        guard_prompt(f"see {uuid.uuid4()}", where="test")


def test_pii_keys_are_refused_even_when_the_value_is_clean() -> None:
    with pytest.raises(PromptPiiError) as exc:
        guard_prompt({"farmer_name": "Ramesh", "crop": "cotton"}, where="test")
    assert "farmer_name" in str(exc.value)


def test_nested_findings_name_their_path() -> None:
    payload = {"records": [{"note": "reach him on 9876543210"}]}
    assert findings(payload) == ["phone-like digit run in 'records[0].note'"]


@pytest.mark.parametrize(
    ("key", "pii"),
    [
        ("name", True),
        ("officer_name", True),
        ("phone_hash", True),
        ("contact_phone", True),
        ("phone_last4", False),
        ("english_name", True),
        ("crop", False),
        ("rule_id", False),
    ],
)
def test_is_pii_key(key: str, pii: bool) -> None:
    assert is_pii_key(key) is pii


def test_scrub_drops_keys_and_masks_numbers() -> None:
    scrubbed = scrub(
        {"farmer_name": "Ramesh", "note": f"call +919876543210 about {RECORD_ID}", "visits": 3}
    )
    assert scrubbed == {"note": f"call ******3210 about {RECORD_ID}", "visits": 3}
    guard_prompt(scrubbed, where="test")


def test_mask_text_keeps_record_ids() -> None:
    masked = mask_text(f"call +919876543210 about {RECORD_ID}")
    assert masked == f"call ******3210 about {RECORD_ID}"
    assert mask_text("closed 2026-09-18, 3 of 5 visits") == "closed 2026-09-18, 3 of 5 visits"


# --------------------------------------------------------------------------- images
def test_exif_is_refused_and_stripped_bytes_pass() -> None:
    from PIL import Image

    photo = Image.new("RGB", (64, 64), (30, 120, 40))
    # EXIF with a GPS IFD pointer: what a field photo carries (SEC-027).
    exif = Image.Exif()
    exif[0x8825] = {1: "N", 2: (17, 23, 6), 3: "E", 4: (78, 29, 12)}
    with_exif = to_jpeg(photo, exif=exif.tobytes())
    with pytest.raises(PromptPiiError, match="image metadata"):
        assert_no_exif(with_exif)
    assert_no_exif(strip_for_llm(with_exif))


# --------------------------------------------------------------------------- prompt shapes
def _request(**overrides: object) -> LlmRequest:
    image = strip_for_llm(synthetic_leaf("DX-TEST", 0))
    base: dict[str, object] = {
        "images": (LlmImage(data=image, blob_uri="gs://b/k", sha256="a" * 64),),
        "crop": "cotton",
        "district": "Warangal",
        "season": "kharif",
        "crop_stage": "flowering",
        "candidates": (
            LlmCandidate(
                problem_id=RECORD_ID,
                english_name="bacterial blight",
                local_name="कपास झुलसा",
                symptoms=("angular water-soaked lesions",),
            ),
        ),
    }
    base.update(overrides)
    return LlmRequest(**base)  # type: ignore[arg-type]


def test_diagnosis_prompt_fields_are_exactly_the_reviewed_set() -> None:
    """Adding a field to LlmRequest without reviewing it in llm_guard fails here."""
    assert {f.name for f in dataclasses.fields(LlmRequest)} == set(DIAGNOSIS_PROMPT_FIELDS)


def test_diagnosis_prompt_passes_the_guard() -> None:
    request = _request()
    guard_request(request)
    assert build_messages(request)
    assert loggable_prompt(request, max_tokens=100, effort="low")


def test_a_future_prompt_field_with_pii_is_refused() -> None:
    """The gate the requirement asks for: a name or a phone in the context stops the call."""
    with pytest.raises(PromptPiiError) as exc:
        build_messages(_request(district="Warangal (farmer Ramesh, +91 98765 43210)"))
    assert GUARD_SITE in str(exc.value)
    assert "phone-like digit run" in str(exc.value)

    with pytest.raises(PromptPiiError):
        build_messages(_request(crop="cotton for ramesh.k@example.com"))

    with pytest.raises(PromptPiiError, match="coordinate pair"):
        build_messages(_request(crop_stage="flowering at 17.385044, 78.486671"))


def test_an_unstripped_image_is_refused() -> None:
    from PIL import Image

    exif = Image.Exif()
    exif[0x8825] = {1: "N"}
    raw = to_jpeg(Image.new("RGB", (32, 32), (10, 90, 20)), exif=exif.tobytes())
    with pytest.raises(PromptPiiError, match="image metadata"):
        build_messages(_request(images=(LlmImage(data=raw, blob_uri="gs://b/k", sha256="b" * 64),)))


def test_flag_bundle_keys_are_the_reviewed_set() -> None:
    """Mirrors build_bundle: the VA-004 prompt shape is pinned in one place."""
    from farmerapp.flags.review_agent import build_bundle

    assert (
        frozenset(
            {"rule", "severity", "subject", "raised_at", "records", "metrics", "map", "photos"}
        )
        == FLAG_BUNDLE_KEYS
    )
    assert build_bundle.__module__ == "farmerapp.flags.review_agent"
