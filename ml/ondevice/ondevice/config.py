"""Single source of truth for labels, the output layout, thresholds and training settings.

The label order and the output layout are part of the mobile contract (INTEGRATION.md) and are
pinned by tests/test_labels.py. Never reorder; append a new label only with a major version bump.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
CACHE_DIR = DATA_DIR / "cache"
MANIFEST = DATA_DIR / "manifest.csv"
SOURCES = DATA_DIR / "sources.json"
RUNS_DIR = ROOT / "runs"
ARTIFACTS_DIR = ROOT / "artifacts"

MODEL_NAME = "crop_quality"
MODEL_VERSION = "ondevice-v1.0"  # ml/ondevice/README.md: ondevice-v<major>.<minor>
TFLITE_NAME = "crop_quality_v1.tflite"
MAX_TFLITE_BYTES = 8 * 1024 * 1024  # DX-001: < 8 MB

# SPEC DX-001: the 6 pilot crops + everything else. Codes match catalog crop codes.
CROP_LABELS: tuple[str, ...] = ("paddy", "cotton", "chilli", "maize", "tomato", "groundnut", "other")
QUALITY_LABELS: tuple[str, ...] = ("ok", "blurry", "dark")

INPUT_SIZE = 224
CACHE_SIZE = 256  # images are cached at 256x256; training crops 224 at random, eval centre-crops

# One float32 output tensor [1, 11], in this order (see INTEGRATION.md).
OUTPUT_LAYOUT: tuple[str, ...] = (
    "plant",
    *(f"quality_{q}" for q in QUALITY_LABELS),
    *(f"crop_{c}" for c in CROP_LABELS),
)


@dataclass(frozen=True)
class Thresholds:
    """Decision thresholds shipped in metadata.json and applied by the app."""

    # p(plant) below this -> "not a plant" retake.
    plant_min: float = 0.5
    # p(blurry) / p(dark) at or above this -> retake with the matching tip.
    blurry_min: float = 0.5
    dark_min: float = 0.5
    # top crop probability below this -> crop_detected_on_device = null (let the user pick).
    crop_min: float = 0.6


@dataclass(frozen=True)
class Degradation:
    """How the quality head's labels are synthesised (tf ops in ondevice/data.py)."""

    p_blurry: float = 0.22
    p_dark: float = 0.18
    # Gaussian sigma in px at 224 input. 'blurry' >= blur_sigma_min; 'ok' images get <= ok_sigma_max.
    blur_sigma_min: float = 2.2
    blur_sigma_max: float = 5.0
    ok_sigma_max: float = 0.6
    # Mean luminance (0..1) targets. Heuristic dark threshold in the app is 0.15.
    dark_lum_min: float = 0.02
    dark_lum_max: float = 0.11
    ok_lum_min: float = 0.2


@dataclass(frozen=True)
class TrainConfig:
    seed: int = 1337
    # ImageNet backbone (see ondevice/model.py for why MobileNetV2 and not V3-Small).
    backbone: str = "mobilenet_v2"
    alpha: float = 1.0
    batch_size: int = 64
    # stage 1: backbone frozen; stage 2: top of the backbone unfrozen.
    head_epochs: int = 4
    finetune_epochs: int = 8
    head_lr: float = 2e-3
    finetune_lr: float = 3e-4
    finetune_from_layer: str = "block_12_expand"  # unfreeze from here to the top (last 5 blocks)
    dropout: float = 0.25
    label_smoothing: float = 0.05
    loss_weights: dict = field(default_factory=lambda: {"plant": 1.0, "quality": 1.0, "crop": 1.0})
    val_fraction: float = 0.15
    test_fraction: float = 0.15
    degradation: Degradation = field(default_factory=Degradation)
    thresholds: Thresholds = field(default_factory=Thresholds)

    def to_dict(self) -> dict:
        return asdict(self)
