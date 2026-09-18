#!/usr/bin/env bash
# Mobile workspace check: the same steps as ci-mobile.yml (SPEC 10.3).
# Called by the root Makefile: `cd apps/mobile && ./tool/check.sh`.
#
# Env:
#   APK_SIZE_CHECK=1   also build the farmer release APK and enforce < 25 MB.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

step() { printf '\n==> %s\n' "$*"; }

step "flutter pub get (workspace)"
flutter pub get

step "code generation: tokens, l10n, drift"
(cd packages/core && dart run tool/gen_tokens.dart)
(cd packages/core && flutter gen-l10n)
(cd packages/core && dart run build_runner build --delete-conflicting-outputs)

step "dart format --set-exit-if-changed"
dart format --output=none --set-exit-if-changed .

step "flutter analyze (zero issues)"
for pkg in packages/core apps/agent apps/farmer; do
  (cd "$pkg" && flutter analyze --no-pub)
done

step "i18n string lint"
dart run tool/lint_strings.dart

step "flutter test"
for pkg in packages/core apps/agent apps/farmer; do
  (cd "$pkg" && flutter test --no-pub)
done

if [[ "${APK_SIZE_CHECK:-0}" == "1" ]]; then
  step "APK size check (farmer release < 25 MB)"
  "$ROOT/tool/apk_size_check.sh"
else
  echo "(skipping APK size check; set APK_SIZE_CHECK=1 to run it)"
fi

printf '\nmobile check: OK\n'
