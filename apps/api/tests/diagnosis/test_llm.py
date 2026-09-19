"""DX-004 / SEC-027: the Claude fallback client against a fake ``AsyncAnthropic``."""

from __future__ import annotations

import base64
import json
import uuid

import pytest

from farmerapp.diagnosis.images import strip_for_llm, synthetic_leaf
from farmerapp.diagnosis.llm import (
    NOT_A_PLANT_MARK,
    SYSTEM_PROMPT,
    UNKNOWN,
    ClaudeDiagnosisClient,
    DisabledLlmClient,
    FakeLlmDiagnosisClient,
    LazyClaudeClient,
    LlmCandidate,
    LlmImage,
    LlmRequest,
    LlmTemporaryError,
    answer_schema,
    parse_answer,
)
from farmerapp.diagnosis.services import build_llm
from farmerapp.settings import Settings
from tests.diagnosis.conftest import (
    FakeAnthropic,
    FakeResponse,
    StopDetails,
    api_status_error,
    connection_error,
)

# Fixed ids: parametrize ids must be identical on every xdist worker.
P1, P2 = "8a1f4c1e-0000-4000-8000-000000000001", "8a1f4c1e-0000-4000-8000-000000000002"
OTHER = "8a1f4c1e-0000-4000-8000-0000000000ff"


def _request(candidates: int = 2) -> LlmRequest:
    data = strip_for_llm(synthetic_leaf("paddy_blast", 3))
    ids = [P1, P2, *[str(uuid.uuid4()) for _ in range(candidates - 2)]][:candidates]
    return LlmRequest(
        images=(LlmImage(data=data, blob_uri="gs://local/t/diagnosis/abc", sha256="a" * 64),),
        crop="Paddy",
        district="Warangal",
        season="kharif",
        crop_stage="vegetative",
        candidates=tuple(
            LlmCandidate(
                problem_id=pid,
                english_name=f"Problem {i}",
                local_name="అగ్గి తెగులు" if i == 0 else None,
                symptoms=("Spindle-shaped spots",),
            )
            for i, pid in enumerate(ids)
        ),
    )


def _answer(problem_id: str, confidence: str = "high", reasoning: str = "Grey spots.") -> str:
    return json.dumps(
        {
            "problem_id": problem_id,
            "confidence": confidence,
            "reasoning": reasoning,
            "visible_symptoms": ["grey spots"],
        }
    )


async def test_request_shape_and_answer() -> None:
    fake = FakeAnthropic([FakeResponse(_answer(P1))])
    client = ClaudeDiagnosisClient(fake, model="claude-opus-5")
    outcome = await client.diagnose(_request())
    assert outcome.status == "answered"
    assert outcome.problem_id == uuid.UUID(P1)
    assert outcome.confidence == "high"
    assert outcome.visible_symptoms == ["grey spots"]
    (call,) = fake.messages.calls
    assert call["model"] == "claude-opus-5"
    assert call["max_tokens"] == 16_000
    assert call["system"] == SYSTEM_PROMPT
    assert "thinking" not in call  # adaptive thinking left at the model default
    output_config = call["output_config"]
    assert output_config["effort"] == "medium"
    assert output_config["format"]["type"] == "json_schema"
    schema = output_config["format"]["schema"]
    assert schema == answer_schema([P1, P2, UNKNOWN])
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {"problem_id", "confidence", "reasoning", "visible_symptoms"}
    content = call["messages"][0]["content"]
    assert content[0]["type"] == "image"
    assert content[0]["source"]["type"] == "base64"
    assert content[0]["source"]["media_type"] == "image/jpeg"
    base64.b64decode(content[0]["source"]["data"], validate=True)
    assert content[-1]["type"] == "text"
    text = content[-1]["text"]
    assert "Crop: Paddy" in text and "District: Warangal" in text and "Season: kharif" in text
    assert P1 in text and "అగ్గి తెగులు" in text
    # the log record: prompt without image bytes, raw output, tokens
    (record,) = outcome.calls
    assert record.outcome == "ok" and record.attempt == 1
    assert record.input_tokens == 1200 and record.output_tokens == 80
    assert record.prompt["images"][0]["blob_uri"] == "gs://local/t/diagnosis/abc"
    assert content[0]["source"]["data"] not in json.dumps(record.prompt)
    assert record.raw_output == _answer(P1)


async def test_unknown_and_not_a_plant() -> None:
    fake = FakeAnthropic(
        [
            FakeResponse(_answer(UNKNOWN, "low", "Unclear photo.")),
            FakeResponse(_answer(UNKNOWN, "high", f"{NOT_A_PLANT_MARK} a wall")),
        ]
    )
    client = ClaudeDiagnosisClient(fake)
    unknown = await client.diagnose(_request())
    assert unknown.problem_id is None and unknown.status == "unknown" and not unknown.not_a_plant
    wall = await client.diagnose(_request())
    assert wall.problem_id is None and wall.not_a_plant


async def test_refusal_is_unknown_with_stop_details_logged() -> None:
    fake = FakeAnthropic([FakeResponse("", stop_reason="refusal", stop_details=StopDetails())])
    outcome = await ClaudeDiagnosisClient(fake).diagnose(_request())
    assert outcome.status == "refusal" and outcome.problem_id is None
    (record,) = outcome.calls
    assert record.outcome == "refusal"
    assert record.stop_details == {"type": "refusal", "category": "bio", "explanation": "declined"}
    assert len(fake.messages.calls) == 1


async def test_max_tokens_retries_once_with_a_larger_budget() -> None:
    fake = FakeAnthropic(
        [FakeResponse('{"problem_id": "', stop_reason="max_tokens"), FakeResponse(_answer(P2))]
    )
    outcome = await ClaudeDiagnosisClient(fake).diagnose(_request())
    assert outcome.problem_id == uuid.UUID(P2)
    assert [c["max_tokens"] for c in fake.messages.calls] == [16_000, 32_000]
    assert [c.outcome for c in outcome.calls] == ["max_tokens", "ok"]
    twice = FakeAnthropic([FakeResponse("", stop_reason="max_tokens")] * 2)
    assert (await ClaudeDiagnosisClient(twice).diagnose(_request())).status == "invalid"


@pytest.mark.parametrize(
    "bad",
    [
        "not json at all",
        json.dumps(
            {"problem_id": P1, "confidence": "certain", "reasoning": "", "visible_symptoms": []}
        ),
        json.dumps({"problem_id": P1, "confidence": "low", "reasoning": "x"}),
        _answer(OTHER),  # a problem outside the candidates
    ],
    ids=["not_json", "bad_enum", "missing_key", "not_a_candidate"],
)
async def test_invalid_answer_is_retried_once_then_unknown(bad: str) -> None:
    """DX-004 acceptance: invalid JSON retried once, then "unknown"."""
    fake = FakeAnthropic([FakeResponse(bad), FakeResponse(bad)])
    outcome = await ClaudeDiagnosisClient(fake).diagnose(_request())
    assert outcome.status == "invalid" and outcome.problem_id is None
    assert len(fake.messages.calls) == 2
    recovered = FakeAnthropic([FakeResponse(bad), FakeResponse(_answer(P1))])
    assert (await ClaudeDiagnosisClient(recovered).diagnose(_request())).problem_id == uuid.UUID(P1)


@pytest.mark.parametrize("status", [429, 500, 529])
async def test_rate_limits_and_server_errors_are_temporary(status: int) -> None:
    fake = FakeAnthropic([api_status_error(status)])
    with pytest.raises(LlmTemporaryError) as info:
        await ClaudeDiagnosisClient(fake).diagnose(_request())
    assert info.value.calls[0].outcome in ("rate_limited", "server_error")


async def test_connection_error_is_temporary_and_client_errors_are_unknown() -> None:
    with pytest.raises(LlmTemporaryError):
        await ClaudeDiagnosisClient(FakeAnthropic([connection_error()])).diagnose(_request())
    outcome = await ClaudeDiagnosisClient(FakeAnthropic([api_status_error(400)])).diagnose(
        _request()
    )
    assert outcome.status == "error" and outcome.calls[0].outcome == "api_error"


def test_parse_answer_rejects_extra_keys() -> None:
    raw = json.dumps(
        {
            "problem_id": P1,
            "confidence": "low",
            "reasoning": "x",
            "visible_symptoms": [],
            "farmer": "?",
        }
    )
    with pytest.raises(ValueError, match="invalid answer"):
        parse_answer(raw, [P1, UNKNOWN])


async def test_stand_ins_and_settings() -> None:
    fake = FakeLlmDiagnosisClient()
    answer = await fake.diagnose(_request())
    assert answer.problem_id == uuid.UUID(P1) and answer.confidence == "medium"
    empty = LlmRequest(
        images=(), crop="x", district=None, season=None, crop_stage=None, candidates=()
    )
    assert (await fake.diagnose(empty)).problem_id is None
    assert (await DisabledLlmClient().diagnose(_request())).status == "disabled"
    assert isinstance(build_llm(Settings(diagnosis_llm="fake")), FakeLlmDiagnosisClient)
    assert isinstance(build_llm(Settings(diagnosis_llm="off")), DisabledLlmClient)
    lazy = build_llm(Settings(diagnosis_llm="claude", diagnosis_llm_model="claude-opus-5"))
    assert isinstance(lazy, LazyClaudeClient) and lazy.model == "claude-opus-5"
