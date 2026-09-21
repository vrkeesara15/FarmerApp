#!/usr/bin/env bash
# SEC-008 — "obfuscation on".
#
#   scripts/mobile/apk_obfuscation_check.sh <app.apk> <symbols-dir> [gradle-file]
#
# Three independent assertions, all fail-closed:
#
#   1. Dart obfuscation ran. `flutter build --obfuscate
#      --split-debug-info=<dir>` is the only thing that writes
#      app.android-*.symbols; if that directory is empty the release was built
#      without --obfuscate and the Dart symbol names are in the snapshot.
#   2. R8 ran over the Java/Kotlin side. Measured on the shipped artefact, not
#      on the build config: the share of DEX classes whose simple name is one
#      or two characters. R8 renames aggressively, so a minified Flutter app
#      sits far above the threshold while an unminified one sits near zero.
#   3. `isMinifyEnabled` / `isShrinkResources` are on and `isDebuggable` is off
#      in the release buildType, so a future edit that turns R8 off is caught
#      at review time as well as by (2).
#
# Requires apkanalyzer (Android SDK cmdline-tools) or dexdump (build-tools).
# A missing tool is exit 2, never a pass.
#
# Env:
#   MIN_SHORT_CLASS_SHARE  minimum share of 1-2 character class names, percent
#                          (default 25)
set -euo pipefail

APK="${1:-}"
SYMBOLS="${2:-}"
GRADLE="${3:-}"
if [[ -z "$APK" || ! -f "$APK" || -z "$SYMBOLS" ]]; then
  echo "usage: apk_obfuscation_check.sh <app.apk> <symbols-dir> [app/build.gradle.kts]" >&2
  exit 2
fi
THRESHOLD="${MIN_SHORT_CLASS_SHARE:-25}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"

fail() { echo "::error::SEC-008 obfuscation check: $*"; exit 1; }

# --- 1. Dart symbols -------------------------------------------------------
if [[ ! -d "$SYMBOLS" ]]; then
  fail "symbol directory $SYMBOLS does not exist — the build did not pass --split-debug-info"
fi
SYM_COUNT=$(find "$SYMBOLS" -type f -size +0c | wc -l | tr -d ' ')
if [[ "$SYM_COUNT" -eq 0 ]]; then
  fail "$SYMBOLS is empty — the build did not pass --obfuscate --split-debug-info"
fi
echo "dart obfuscation: OK ($SYM_COUNT symbol file(s) in $SYMBOLS)"
# The symbols must not also be inside the APK, or obfuscation buys nothing.
if unzip -Z1 "$APK" 2>/dev/null | grep -Eq '\.symbols$'; then
  fail "the APK packages a .symbols file; Dart symbols must ship separately"
fi

# --- 2. R8 minification, measured on the DEX ------------------------------
APKANALYZER="$(command -v apkanalyzer || true)"
if [[ -z "$APKANALYZER" && -x "$SDK/cmdline-tools/latest/bin/apkanalyzer" ]]; then
  APKANALYZER="$SDK/cmdline-tools/latest/bin/apkanalyzer"
fi
DEXDUMP="$(command -v dexdump || true)"
if [[ -z "$DEXDUMP" ]]; then
  DEXDUMP="$(ls -d "$SDK"/build-tools/*/dexdump 2>/dev/null | sort -V | tail -1 || true)"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CLASSES="$WORK/classes.txt"

tool_failed() { # <tool> — a broken tool is exit 2, never a pass
  sed 's/^/  /' "$WORK/tool.err" >&2 || true
  echo "::error::SEC-008 obfuscation check: $1 could not read $APK, so the gate did not run" >&2
  exit 2
}

if [[ -n "$APKANALYZER" ]]; then
  # `dex packages` prints: <C|M|F|P> <x|k|r|d> <refs> <decls> <size> <name>
  "$APKANALYZER" dex packages --defined-only "$APK" \
    >"$WORK/dex.txt" 2>"$WORK/tool.err" || tool_failed "apkanalyzer ($APKANALYZER)"
  awk '$1 == "C" { print $NF }' "$WORK/dex.txt" >"$CLASSES"
  SOURCE="apkanalyzer"
elif [[ -n "$DEXDUMP" && -x "$DEXDUMP" ]]; then
  unzip -qq -o "$APK" 'classes*.dex' -d "$WORK/dex" \
    || fail "the APK contains no classes*.dex"
  # "  Class descriptor  : 'La/b/c;'"
  "$DEXDUMP" -f "$WORK"/dex/classes*.dex \
    >"$WORK/dex.txt" 2>"$WORK/tool.err" || tool_failed "dexdump ($DEXDUMP)"
  sed -n "s/.*Class descriptor *: *'L\(.*\);'.*/\1/p" "$WORK/dex.txt" | tr '/' '.' >"$CLASSES"
  SOURCE="dexdump"
else
  echo "::error::SEC-008 obfuscation check: neither apkanalyzer (cmdline-tools) nor" \
    "dexdump (build-tools) found under $SDK — install the Android SDK command-line" \
    "tools; this gate never passes without them" >&2
  exit 2
fi

TOTAL=$(grep -c . "$CLASSES" || true)
[[ "$TOTAL" -gt 100 ]] || fail "only $TOTAL classes read from the DEX via $SOURCE — the check did not run"
# Simple name = the segment after the last '.', ignoring R8's inner-class '$'.
SHORT=$(awk -F. '{ n = $NF; sub(/\$.*/, "", n); if (length(n) <= 2 && length(n) > 0) c++ } END { print c + 0 }' "$CLASSES")
SHARE=$(awk -v s="$SHORT" -v t="$TOTAL" 'BEGIN { printf "%d", (s * 100) / t }')
echo "r8 minification: $SHORT/$TOTAL classes have 1-2 character names (${SHARE}%, via $SOURCE, need >= ${THRESHOLD}%)"
if [[ "$SHARE" -lt "$THRESHOLD" ]]; then
  fail "DEX class names are not minified (${SHARE}% < ${THRESHOLD}%) — isMinifyEnabled is off for this build"
fi

# --- 3. release buildType in the Gradle config -----------------------------
if [[ -n "$GRADLE" ]]; then
  [[ -f "$GRADLE" ]] || fail "$GRADLE not found"
  BLOCK="$(awk '/release[[:space:]]*\{/,/^[[:space:]]{8}\}/' "$GRADLE")"
  grep -q 'isMinifyEnabled[[:space:]]*=[[:space:]]*true' <<<"$BLOCK" \
    || fail "isMinifyEnabled is not true in the release buildType of $GRADLE"
  grep -q 'isShrinkResources[[:space:]]*=[[:space:]]*true' <<<"$BLOCK" \
    || fail "isShrinkResources is not true in the release buildType of $GRADLE"
  if grep -q 'isDebuggable[[:space:]]*=[[:space:]]*true' <<<"$BLOCK"; then
    fail "isDebuggable is true in the release buildType of $GRADLE"
  fi
  echo "gradle release buildType: OK (minify + shrink on, not debuggable)"
fi

echo "apk_obfuscation_check: OK"
