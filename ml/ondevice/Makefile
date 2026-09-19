# ml/ondevice — DX-001 on-device model. Run from this directory: make setup data train eval export bench test
UV ?= uv
RUN := $(UV) run --frozen python

.PHONY: help setup data download prepare train eval export bench test all clean

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

setup: ## create .venv from uv.lock (Python 3.12, TensorFlow 2.21, LiteRT 2.2)
	$(UV) sync --frozen

download: ## fetch the pinned public datasets into data/raw/ (~1.4 GB, sha256-checked)
	$(RUN) data/download.py

prepare: ## build data/cache/ + data/manifest.csv (deterministic sampling and split)
	$(RUN) data/prepare.py

data: download prepare ## download + prepare

train: ## train runs/latest/model.keras
	$(RUN) train.py --out runs/latest

eval: ## evaluate the Keras checkpoint on the test split -> runs/latest/eval_keras.{json,md}
	$(RUN) eval.py --keras runs/latest/model.keras

export: ## int8 TFLite + metadata.json + TFLite test-split evaluation -> artifacts/
	$(RUN) export.py --keras runs/latest/model.keras --out artifacts

bench: ## LiteRT / XNNPACK latency on this machine -> artifacts/bench_mac.json
	$(RUN) bench.py --model artifacts/crop_quality_v1.tflite --out artifacts/bench_mac.json

test: ## pytest: data pipeline, label order, export size and interpreter shapes
	$(UV) run --frozen pytest

all: setup data train eval export bench test ## full path

clean: ## remove local runs (keeps data/ and committed artifacts/)
	rm -rf runs
