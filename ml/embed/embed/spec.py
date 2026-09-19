"""The one pinned encoder this service serves (DX-002, DX-005).

``NAME`` / ``VERSION`` are the contract identity the API pins (``DIAGNOSIS_ENCODER_NAME`` /
``DIAGNOSIS_ENCODER_VERSION``, docs/prs/M6-diagnosis-api.md); ``REVISION`` is the exact Hugging Face
commit the weights come from and ``WEIGHTS_SHA256`` the sha256 of that commit's ``model.safetensors``
(checked on download). Changing any of these is a **new encoder version**: bump ``VERSION``, re-embed
the whole corpus (DX-012) and move the API pin in the same release — vectors of two encoders are never
mixed in one kNN.
"""

from __future__ import annotations

NAME = "siglip-base-patch16-224"
VERSION = "2024-01"  # weights released 2024-01; later commits only touched the README / tokenizer
DIM = 768

HF_REPO = "google/siglip-base-patch16-224"
REVISION = "7fd15f0689c79d79e38b1c2e2e2370a7bf2761ed"
WEIGHTS_FILE = "model.safetensors"
WEIGHTS_SHA256 = "2c63cb7d1f2e95ba501893cbb8faeb4ea9a3af295498d35097126228659c2af8"
WEIGHTS_BYTES = 812_672_320
LICENCE = "Apache-2.0"

#: Files fetched from the pinned revision (the text tower's tokenizer is not needed).
FILES = ("config.json", "preprocessor_config.json", WEIGHTS_FILE)

#: Written next to the saved vision tower by ``embed.fetch``; read at startup.
MANIFEST = "embed_manifest.json"
