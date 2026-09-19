"""Problem codes of the diagnosis and corpus APIs (RFC 9457 ``code``)."""

from __future__ import annotations

from farmerapp.api.errors import AppError


class InvalidCorpusTransitionError(AppError):
    status = 409
    code = "invalid_transition"


class CorpusProblemExistsError(AppError):
    status = 409
    code = "corpus_problem_exists"


class CorpusImageExistsError(AppError):
    status = 409
    code = "corpus_image_exists"


class CorpusEntryLockedError(AppError):
    """Approved / retired entries are immutable: retire and create a new one."""

    status = 409
    code = "corpus_entry_locked"


class CorpusProblemInvalidError(AppError):
    status = 422
    code = "corpus_problem_invalid"


class DiagnosisImageMissingError(AppError):
    """A photo is not a completed upload of the tenant (upload it first)."""

    status = 422
    code = "diagnosis_image_missing"


class ImageShaMismatchError(AppError):
    status = 422
    code = "image_sha_mismatch"


class DiagnosisInvalidError(AppError):
    status = 422
    code = "diagnosis_invalid"


class DiagnosisNotReviewableError(AppError):
    status = 409
    code = "diagnosis_not_reviewable"


class DiagnosisAlreadyReviewedError(AppError):
    """FM-006: an agronomist already answered the case; there is nothing to escalate."""

    status = 409
    code = "diagnosis_already_reviewed"


class ReviewInvalidError(AppError):
    status = 422
    code = "review_invalid"


class EncoderUnavailableError(AppError):
    status = 503
    code = "encoder_unavailable"


__all__ = [
    "CorpusEntryLockedError",
    "CorpusImageExistsError",
    "CorpusProblemExistsError",
    "CorpusProblemInvalidError",
    "DiagnosisAlreadyReviewedError",
    "DiagnosisImageMissingError",
    "DiagnosisInvalidError",
    "DiagnosisNotReviewableError",
    "EncoderUnavailableError",
    "ImageShaMismatchError",
    "InvalidCorpusTransitionError",
    "ReviewInvalidError",
]
