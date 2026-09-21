#!/usr/bin/env bash
# SEC-008 — "no secrets in APK".
#
#   scripts/mobile/apk_secret_scan.sh <app.apk> [env-file ...]
#
# Unpacks the APK and searches every entry (dex, resources, assets, native
# libraries) for
#   1. well-known credential shapes (Google/AWS/Anthropic/Razorpay/GitHub/Slack
#      keys, PEM private key blocks, JWTs), and
#   2. the literal values of the repository's own .env / .env.example, so a
#      developer secret that leaked into a --dart-define or an asset is caught
#      even when it matches no known shape.
#
# Output discipline: a hit prints the *pattern name* and the *APK entry* only,
# never the matched text — CI logs are readable by anyone with repo access, so
# the scanner must not become the thing that leaks the key.
#
# Exit 0 clean, 1 on any hit, 2 on a usage/tooling problem (never a silent pass).
#
# Env:
#   SECRET_SCAN_IGNORE_ENTRIES  ERE of APK entries to skip (third-party asset
#                               blobs with known false positives). Every use
#                               must be justified in docs/runbooks/mobile-security-scan.md.
set -euo pipefail

APK="${1:-}"
if [[ -z "$APK" || ! -f "$APK" ]]; then
  echo "usage: apk_secret_scan.sh <app.apk> [env-file ...]" >&2
  exit 2
fi
shift || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
declare -a ENV_FILES=()
for arg in "$@"; do ENV_FILES+=("$arg"); done
if [[ ${#ENV_FILES[@]} -eq 0 ]]; then
  for f in "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"; do
    if [[ -f "$f" ]]; then ENV_FILES+=("$f"); fi
  done
fi

command -v unzip >/dev/null || { echo "unzip is required" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# known credential shapes: "name<TAB>ERE"
# ---------------------------------------------------------------------------
# `ghp_`/`xox`/`sk-` are anchored with a length so that the literal prefix
# appearing in a help string or a docs asset is not reported as a key.
read -r -d '' PATTERNS <<'EOF' || true
google_api_key	AIza[0-9A-Za-z_-]{35}
anthropic_api_key	sk-ant-[A-Za-z0-9_-]{16,}
openai_style_key	sk-[A-Za-z0-9]{20,}
razorpay_live_key	rzp_live_[A-Za-z0-9]{6,}
aws_access_key_id	AKIA[0-9A-Z]{16}
pem_private_key	-----BEGIN [A-Z ]*PRIVATE KEY-----
github_token	gh[pousr]_[A-Za-z0-9]{30,}
jwt	eyJhbGciOi[A-Za-z0-9_-]{5,}
slack_token	xox[baprs]-[A-Za-z0-9-]{10,}
EOF

# ---------------------------------------------------------------------------
# secrets taken from the repository's own env files
# ---------------------------------------------------------------------------
# Only values that could plausibly be a real credential are searched for: at
# least 12 characters and not one of our documented placeholders. Everything
# in .env.example is a placeholder by policy (CLAUDE.md: "No secrets in code,
# fixtures or logs"), so in CI this list is usually short — its real job is to
# catch a developer's local .env leaking into a build.
# Substrings that mark a value as a documented placeholder rather than a
# credential. Deliberately broad: a *false failure* on a harmless constant
# that legitimately ships in the app (a model id, a bucket name) costs a
# release, while a real production secret never contains "mock" or "dev-only".
PLACEHOLDER='localhost|127\.0\.0\.1|example|REPLACE|CHANGEME|changeme|placeholder|dev-only|not-a-secret|TODO|<|\$\{|mock|fake|dummy|sample|test|-local|_local'
declare -a ENV_NAMES=() ENV_VALUES=()
for envf in "${ENV_FILES[@]}"; do
  if [[ ! -f "$envf" ]]; then continue; fi
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then continue; fi
    name="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    value="${value%%  #*}"                       # trailing inline comment
    value="$(printf '%s' "$value" | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
    if [[ ${#value} -lt 12 ]]; then continue; fi
    if [[ "$value" == \[* ]]; then continue; fi  # JSON list, not a credential
    if grep -Eqi -- "$PLACEHOLDER" <<<"$value"; then continue; fi
    ENV_NAMES+=("$(basename "$envf"):$name")
    ENV_VALUES+=("$value")
  done <"$envf"
done

echo "apk_secret_scan: $(basename "$APK")"
echo "  known patterns: $(grep -c . <<<"$PATTERNS")"
echo "  env values from ${#ENV_FILES[@]} file(s): ${#ENV_VALUES[@]}"
if [[ ${#ENV_NAMES[@]} -gt 0 ]]; then
  echo "  env keys checked: ${ENV_NAMES[*]}"
fi

# ---------------------------------------------------------------------------
# unpack and scan
# ---------------------------------------------------------------------------
unzip -qq -o "$APK" -d "$WORK/apk"

HITS=0
report() { # <pattern-name> <apk entry>
  echo "::error::SEC-008 possible secret in APK: pattern '$1' matched entry '$2'"
  HITS=$((HITS + 1))
}

# A packaged .env is a finding by itself, whatever is in it.
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  report "packaged-dotenv" "$entry"
done < <(cd "$WORK/apk" && find . -name '.env' -o -name '.env.*' | sed 's|^\./||')

emit_strings() { # printable runs of >= 8 chars, text or binary
  if command -v strings >/dev/null; then
    strings -a -n 8 "$1" 2>/dev/null || true
  else
    LC_ALL=C tr -c '[:print:]' '\n' <"$1" 2>/dev/null | awk 'length($0) >= 8' || true
  fi
}

SCANNED=0
while IFS= read -r file; do
  entry="${file#"$WORK/apk/"}"
  if [[ -n "${SECRET_SCAN_IGNORE_ENTRIES:-}" ]] && grep -Eq -- "$SECRET_SCAN_IGNORE_ENTRIES" <<<"$entry"; then
    continue
  fi
  emit_strings "$file" >"$WORK/strings.txt"
  SCANNED=$((SCANNED + 1))

  while IFS=$'\t' read -r pname pregex; do
    [[ -n "$pname" ]] || continue
    if grep -Eq -- "$pregex" "$WORK/strings.txt"; then
      report "$pname" "$entry"
    fi
  done <<<"$PATTERNS"

  if [[ ${#ENV_VALUES[@]} -gt 0 ]]; then
    for i in "${!ENV_VALUES[@]}"; do
      if grep -Fq -- "${ENV_VALUES[$i]}" "$WORK/strings.txt"; then
        report "env-value:${ENV_NAMES[$i]}" "$entry"
      fi
    done
  fi
done < <(find "$WORK/apk" -type f)

echo "  scanned $SCANNED entries"
if [[ $HITS -gt 0 ]]; then
  echo "apk_secret_scan: FAILED with $HITS hit(s)." >&2
  echo "Triage: docs/runbooks/mobile-security-scan.md#a-gate-fired" >&2
  exit 1
fi
echo "apk_secret_scan: OK (no known credential shapes, no env values, no packaged .env)"
