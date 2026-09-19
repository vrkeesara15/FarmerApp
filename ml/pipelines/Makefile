# ml/pipelines — DX-012 Vertex AI pipelines. Run from this directory: make compile | make check
UV ?= uv
KFP := $(UV) run --no-project --python 3.12 --with kfp==2.13.0 python retrain_pipeline.py

.PHONY: help compile check

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

compile: ## compile the pipelines into compiled/ (commit the YAML)
	$(KFP) --out compiled

check: ## compile into a temp directory and diff against compiled/ (the YAML must be current)
	@tmp=$$(mktemp -d); $(KFP) --out $$tmp >/dev/null; diff -r compiled $$tmp && echo "pipelines up to date"; \
	  status=$$?; rm -rf $$tmp; exit $$status
