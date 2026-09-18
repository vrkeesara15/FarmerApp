#!/usr/bin/env bash
# Builds the farmer app release APK and fails if it exceeds the budget
# (ci-mobile.yml: "APK size check (farmer < 25 MB)").
#
# Env:
#   APK_MAX_MB   budget in MB (default 25)
set -euo pipefail

cd "$(dirname "$0")/../apps/farmer"
MAX_MB="${APK_MAX_MB:-25}"

if ! flutter doctor 2>/dev/null | grep -q '\[✓\] Android toolchain'; then
  echo "Android toolchain not available; cannot build the APK." >&2
  exit 2
fi

# Play delivers one ABI per device (AAB splits), so the budget applies to the
# largest per-ABI APK, not the fat multi-ABI APK. x86_64 is not shipped.
flutter build apk --release --no-pub --split-per-abi \
  --target-platform android-arm,android-arm64
OUT="build/app/outputs/flutter-apk"
LARGEST=""
LARGEST_BYTES=0
for apk in "$OUT"/app-armeabi-v7a-release.apk "$OUT"/app-arm64-v8a-release.apk; do
  if [[ ! -f "$apk" ]]; then
    echo "APK not found at $apk" >&2
    exit 1
  fi
  BYTES=$(stat -f %z "$apk" 2>/dev/null || stat -c %s "$apk")
  MB=$(awk -v b="$BYTES" 'BEGIN { printf "%.2f", b / 1048576 }')
  echo "$(basename "$apk"): ${MB} MB"
  if (( BYTES > LARGEST_BYTES )); then LARGEST_BYTES=$BYTES; LARGEST=$apk; fi
done

MB=$(awk -v b="$LARGEST_BYTES" 'BEGIN { printf "%.2f", b / 1048576 }')
echo "largest per-ABI APK: $(basename "$LARGEST") ${MB} MB (budget ${MAX_MB} MB)"
if awk -v b="$LARGEST_BYTES" -v m="$MAX_MB" 'BEGIN { exit !(b > m * 1048576) }'; then
  echo "APK exceeds the ${MAX_MB} MB budget" >&2
  exit 1
fi
echo "APK size check: OK"
