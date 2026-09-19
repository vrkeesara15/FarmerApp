#!/usr/bin/env bash
# Release build of one app for one environment (SEC-008, SEC-024).
#   usage: tool/build_release.sh <agent|farmer> <dev|stg|prd> [apk|appbundle]
#
# * --dart-define-from-file=config/env/<env>.json: API_BASE_URL,
#   API_CERT_PINS (primary,backup SPKI SHA-256), PLAY_INTEGRITY_PROJECT_NUMBER.
# * --obfuscate --split-debug-info: Dart symbols stay in build/symbols/<app>/
#   (upload them to Crashlytics / keep them with the release, never ship them).
# * R8 shrinking + obfuscation, never debuggable: android/app/build.gradle.kts.
# * The merged manifest is checked (tool/check_release_manifest.sh).
# Publishing to Play Console is human-only (CLAUDE.md).
set -euo pipefail

APP="${1:?usage: build_release.sh <agent|farmer> <dev|stg|prd> [apk|appbundle]}"
ENV_NAME="${2:?usage: build_release.sh <agent|farmer> <dev|stg|prd> [apk|appbundle]}"
KIND="${3:-appbundle}"
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TOOL_DIR/.." && pwd)"
CONFIG="$ROOT/config/env/$ENV_NAME.json"

[[ "$APP" == agent || "$APP" == farmer ]] || { echo "unknown app $APP" >&2; exit 2; }
[[ -f "$CONFIG" ]] || { echo "no config $CONFIG" >&2; exit 2; }
if [[ "$ENV_NAME" != dev ]] && grep -q 'REPLACE_WITH' "$CONFIG"; then
  echo "warning: $CONFIG still has placeholder certificate pins; this build" \
    "refuses every TLS connection to the API until real pins are set" >&2
fi

cd "$ROOT/apps/$APP"
flutter build "$KIND" --release \
  --dart-define-from-file="$CONFIG" \
  --obfuscate --split-debug-info="build/symbols/$ENV_NAME"

if [[ "$KIND" == apk ]]; then
  "$TOOL_DIR/check_release_manifest.sh" build/app/outputs/flutter-apk/app-release.apk
fi
