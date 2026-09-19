#!/usr/bin/env bash
# Local equivalent of ci-infra.yml's static job (SPEC 9.7):
#   terraform fmt -check, init -backend=false + validate for bootstrap and every env,
#   terraform test of every module with a tests/ directory (settings contract: run_service,
#   run_job; connection budget: db_budget), then tflint and checkov when installed (SKIP with
#   a message otherwise).
# Usage: cd infra && ./scripts/check.sh
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$INFRA_DIR"

# Share provider downloads between the five init runs.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
export TF_IN_AUTOMATION=1
mkdir -p "$TF_PLUGIN_CACHE_DIR"

DIRS=(bootstrap envs/dev envs/stg envs/prd)
status=0

step() { printf '\n==> %s\n' "$*"; }

step "terraform fmt -check -recursive"
if ! terraform fmt -check -recursive -diff; then
  echo "FAIL: run 'terraform fmt -recursive' in infra/" >&2
  status=1
fi

for d in "${DIRS[@]}"; do
  step "terraform validate: $d"
  (
    cd "$d"
    terraform init -backend=false -input=false -no-color >/dev/null
    terraform validate -no-color
  ) || status=1
done

# Module tests (modules/*/tests: mock providers or none, no credentials needed). The same
# discovery runs in ci-infra.yml, so a new tests/ directory is picked up by both.
TEST_DIRS=()
while IFS= read -r t; do TEST_DIRS+=("$(dirname "$t")"); done \
  < <(find modules -mindepth 2 -maxdepth 2 -type d -name tests -not -path '*/.terraform/*' | sort)
if [ "${#TEST_DIRS[@]}" -eq 0 ]; then
  echo "FAIL: no modules/*/tests found" >&2
  status=1
fi
for d in "${TEST_DIRS[@]}"; do
  step "terraform test: $d"
  (
    cd "$d"
    terraform init -backend=false -input=false -no-color >/dev/null
    terraform test -no-color
  ) || status=1
done

step "tflint"
if command -v tflint >/dev/null 2>&1; then
  tflint --init >/dev/null
  tflint --recursive --config "$INFRA_DIR/.tflint.hcl" || status=1
else
  echo "SKIP: tflint not installed (brew install tflint)"
fi

step "checkov"
if command -v checkov >/dev/null 2>&1; then
  checkov --directory . --framework terraform --config-file .checkov.yaml --quiet || status=1
else
  echo "SKIP: checkov not installed (pipx install checkov)"
fi

if [ "$status" -ne 0 ]; then
  echo
  echo "infra checks FAILED" >&2
  exit "$status"
fi
echo
echo "infra checks passed"
