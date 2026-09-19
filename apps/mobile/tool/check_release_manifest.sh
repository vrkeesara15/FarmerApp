#!/usr/bin/env bash
# SEC-008: inspects the merged manifest of a release APK.
#   usage: tool/check_release_manifest.sh <path/to/app-release.apk>
# Fails when the APK is debuggable, allows backup, has no data extraction
# rules or network security config, or permits cleartext traffic globally.
set -euo pipefail

APK="${1:?usage: check_release_manifest.sh <apk>}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
AAPT2="$(ls -d "$SDK"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)"
if [[ -z "$AAPT2" || ! -x "$AAPT2" ]]; then
  echo "aapt2 not found under $SDK/build-tools" >&2
  exit 2
fi

TREE="$("$AAPT2" dump xmltree --file AndroidManifest.xml "$APK")"
fail() { echo "release manifest check failed: $*" >&2; exit 1; }

# android:debuggable must be absent or false.
if grep -Eq 'A: http://schemas.android.com/apk/res/android:debuggable\(0x[0-9a-f]+\)=(true|0xffffffff)' <<<"$TREE"; then
  fail "android:debuggable is true"
fi
grep -Eq 'android:allowBackup\(0x[0-9a-f]+\)=false' <<<"$TREE" \
  || fail "android:allowBackup is not false"
grep -q 'android:dataExtractionRules' <<<"$TREE" \
  || fail "android:dataExtractionRules missing"
grep -q 'android:fullBackupContent' <<<"$TREE" \
  || fail "android:fullBackupContent missing"
grep -q 'android:networkSecurityConfig' <<<"$TREE" \
  || fail "android:networkSecurityConfig missing"
if grep -Eq 'android:usesCleartextTraffic\(0x[0-9a-f]+\)=true' <<<"$TREE"; then
  fail "android:usesCleartextTraffic is true"
fi

# The release network security config (res/xml) must not permit cleartext.
NSC="$("$AAPT2" dump xmltree --file res/xml/network_security_config.xml "$APK" 2>/dev/null || true)"
if [[ -z "$NSC" ]]; then
  # R8 resource shrinking may obfuscate resource paths; find it by content.
  NSC="$(for f in $(unzip -Z1 "$APK" 'res/*.xml' 2>/dev/null); do
    out="$("$AAPT2" dump xmltree --file "$f" "$APK" 2>/dev/null || true)"
    if grep -q 'E: network-security-config' <<<"$out"; then echo "$out"; fi
  done)"
fi
[[ -n "$NSC" ]] || fail "network security config not found in the APK"
if grep -Eq 'cleartextTrafficPermitted\(0x[0-9a-f]+\)=true' <<<"$NSC"; then
  fail "the release network security config permits cleartext"
fi

echo "release manifest OK: $(basename "$APK") (not debuggable, no backup, extraction rules, TLS only)"
