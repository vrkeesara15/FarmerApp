# Mobile release security scan (SEC-008)

Owner: mobile lead (security owner for accepted findings). Severity when it fires: the release
is blocked — sev 3 unless a real secret shipped, which is sev 1 and escalates to
[suspected data breach](suspected-data-breach.md).

SPEC 11.1 SEC-008: *"Mobile: no secrets in APK, no debuggable release, obfuscation on — MobSF
scan in mobile-release.yml"*. This runbook covers the four gates in
[`.github/workflows/mobile-release.yml`](../../.github/workflows/mobile-release.yml), how to
reproduce each on a local release APK, what to do when one fires, and which gates stay human.

## The artefact the gates read

`flutter build appbundle` produces an AAB, whose `AndroidManifest.xml` is **binary XML (AXML)**
— a string-pool format, not text. The old gate grepped those bytes for the ASCII string
`debuggable`, which proves nothing in either direction: the attribute name lives in the string
pool whether or not it is set, and its *value* is a packed integer that never appears as text.

So the first step now assembles the universal APK Play would install:

```
bundletool build-apks --bundle=app-release.aab --mode=universal \
  --ks=<throwaway key> --output=universal.apks
```

and every gate below reads `build/app-release-universal.apk` — the same bytes MobSF gets.
The throwaway key exists only so bundletool will emit an APK; the real upload key is untouched.

## The four gates

| # | Gate | Script | Asserts | Fails when |
|---|---|---|---|---|
| 1 | Release manifest | [`apps/mobile/tool/check_release_manifest.sh`](../../apps/mobile/tool/check_release_manifest.sh) | `android:debuggable` absent or false; `allowBackup=false`; `dataExtractionRules`, `fullBackupContent`, `networkSecurityConfig` present; no global cleartext; the network security config does not permit cleartext | any assertion fails (exit 1), **or aapt2 is missing (exit 2)** |
| 2 | Obfuscation | [`scripts/mobile/apk_obfuscation_check.sh`](../../scripts/mobile/apk_obfuscation_check.sh) | `build/symbols` holds Dart symbol files; no `.symbols` inside the APK; ≥ 25% of DEX classes have 1–2 character names (R8 ran); `isMinifyEnabled`/`isShrinkResources` true and `isDebuggable` not true in the release buildType | any assertion fails (exit 1), **or neither apkanalyzer nor dexdump is available (exit 2)** |
| 3 | Secrets | [`scripts/mobile/apk_secret_scan.sh`](../../scripts/mobile/apk_secret_scan.sh) | no known credential shape and no repo env value anywhere in the APK; no packaged `.env` | any hit (exit 1) |
| 4 | MobSF | [`scripts/mobile/mobsf_gate.py`](../../scripts/mobile/mobsf_gate.py) | high findings ≤ `MOBSF_HIGH_LIMIT` (0); zero `secrets` findings | over the limit, any secret, an unreadable/empty report, an unrecognised schema, **or the container never starts** |

Every one of these fails closed. The previous `|| true` on the manifest step is gone: a missing
tool is a failed job, never a silent pass.

### Gate 1 — release manifest

Reads the merged manifest with `aapt2 dump xmltree`, so `android:debuggable` is judged by its
*resolved value*, not by a substring.

`android:extractNativeLibs` is deliberately **true** in our builds: `useLegacyPackaging = true`
in `android/app/build.gradle.kts` keeps the native libraries compressed so the farmer APK stays
under the 25 MB budget (FM-014). That is a size decision, not a security one, so the gate does
not assert it false. If the budget ever allows uncompressed libraries, flip both together.

### Gate 2 — obfuscation

Three independent signals, because each alone is weak:

1. **Dart.** `--obfuscate --split-debug-info=build/symbols` is the only thing that writes
   `app.android-*.symbols`. An empty or absent symbol directory means the release was built
   without `--obfuscate`, so the Dart symbol names are still in the snapshot. The gate also
   asserts no `.symbols` file is *inside* the APK — shipping the map undoes the obfuscation.
2. **R8, measured on the shipped DEX.** `apkanalyzer dex packages --defined-only` lists every
   defined class; the gate computes the share whose simple name is one or two characters. R8
   renames aggressively, so a minified Flutter app sits far above the 25% threshold and an
   unminified one sits near zero. Tune with `MIN_SHORT_CLASS_SHARE` only with a reason — if a
   new `-keep` rule in `proguard-rules.pro` drags the share down, the right fix is usually a
   narrower `-keep`. Falls back to `dexdump` from build-tools when apkanalyzer is unavailable.
3. **Gradle config.** `isMinifyEnabled`/`isShrinkResources` true, `isDebuggable` not true, in
   the `release` buildType. This catches an edit at review time; (2) catches it in the artefact.

### Gate 3 — secrets

Unzips the APK and runs printable-string extraction over **every** entry — dex, resources,
assets and native `.so` files — then searches for:

- **known credential shapes**: `AIza…` (Google API key), `sk-ant-…`, `sk-…` (OpenAI-style),
  `rzp_live_…`, `AKIA…` (AWS), `-----BEGIN … PRIVATE KEY-----`, `ghp_/gho_/ghu_/ghs_/ghr_…`,
  `eyJhbGciOi…` (JWT), `xox[baprs]-…` (Slack);
- **our own env values**: every `NAME=value` in the repo `.env.example` (and `.env` when
  present locally) whose value is ≥ 12 characters and is not a documented placeholder. This is
  what catches a real secret that matches no known shape — a developer's local `.env` value
  baked in through a `--dart-define`, say;
- **a packaged `.env`**, which is a finding on its own whatever it contains.

**The scanner never prints the matched value.** A hit prints only the pattern name and the APK
entry, so the CI log cannot itself become the leak. That discipline applies to triage too: do
not paste the value into an issue or a Slack thread.

Placeholder filtering is deliberately broad (`mock`, `fake`, `test`, `dev-only`,
`not-a-secret`, `localhost`, `-local`, …) because a false failure on a harmless constant that
legitimately ships — a model id, a bucket name — costs a release, while a real production
secret never contains those words. Everything in `.env.example` is a placeholder by policy
(CLAUDE.md: *"No secrets in code, fixtures or logs"*), so in CI the env list is short by design.

`SECRET_SCAN_IGNORE_ENTRIES` (an ERE over APK entry names) exists for a third-party asset blob
with a known false positive. Every use must be justified here, in this file, with the entry and
why it is safe.

### Gate 4 — MobSF

Runs the free OSS image `opensecurity/mobile-security-framework-mobsf:latest` in docker — no
account, no paid tier, no data leaves the runner. The job uploads the same universal APK,
scans it, pulls `report_json` and hands it to `scripts/mobile/mobsf_gate.py`.

**If the container cannot start — image pull failure, no docker, API never answers within four
minutes — the job FAILS.** The only escape hatch is the repository variable
`vars.MOBSF_OPTIONAL = 'true'`, which downgrades an unavailable MobSF to a warning. Set it only
for a known upstream outage, with an issue tracking its removal, and never to get a release out
past a MobSF *finding* (it does not do that — findings still fail).

## Reading the MobSF report

`mobsf-report.json` is attached to every run as a build artefact. The sections that matter:

| Section | What to read | Our gate |
|---|---|---|
| `appsec` | `security_score` (0–100) and `app_sec_grade`; `high` is MobSF's own curated high list | `appsec.high` counts toward the high total; the score is printed for trend, not gated |
| `manifest_analysis.manifest_findings` | exported components, `debuggable`, `allowBackup`, cleartext, task hijacking | `severity == high` counts |
| `code_analysis.findings` | per-rule, keyed by rule id, severity under `metadata.severity`: weak crypto, insecure random, WebView settings, logging of sensitive data | `metadata.severity == high` counts |
| `secrets` | strings MobSF believes are hardcoded credentials | **any entry fails the gate** |
| `certificate_analysis.certificate_findings` | signature algorithm (SHA1 is high), v1-only signing, debug certificate | `severity == high` counts |
| `network_security.network_findings` | cleartext-permitted domains, trust anchors, pinning | `severity == high` counts |
| `permissions`, `trackers` | review by eye — a new dangerous permission or tracker needs a privacy review (SPEC 14), not just a security one | not gated |

The gate is defensive about all of this: a section MobSF renames degrades to "no findings from
that section" rather than a traceback, **and it prints which sections it actually read**. If
that list is short or says `NONE`, the schema moved and the gate refuses to report a clean
scan — treat it as a gate failure, not a pass.

Secrets are printed as `sha256:<12 hex> (<n> chars)`, never as the value. Open the artefact to
see what it actually found.

<a id="a-gate-fired"></a>
## When a gate fires

### Reproduce locally first

```bash
# 1. build the release exactly as CI does (obfuscated, symbols split out)
cd apps/mobile/apps/farmer
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols

# 2. the universal APK the gates read
curl -sSfL -o /tmp/bundletool.jar \
  https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar
keytool -genkeypair -v -keystore /tmp/analysis.jks -storepass analysis -keypass analysis \
  -alias analysis -keyalg RSA -keysize 2048 -validity 1 -dname "CN=apk analysis" >/dev/null
java -jar /tmp/bundletool.jar build-apks \
  --bundle=build/app/outputs/bundle/release/app-release.aab \
  --output=/tmp/universal.apks --mode=universal --overwrite \
  --ks=/tmp/analysis.jks --ks-pass=pass:analysis \
  --ks-key-alias=analysis --key-pass=pass:analysis
unzip -o -q /tmp/universal.apks -d /tmp/universal
cp /tmp/universal/universal.apk build/app-release-universal.apk

# 3. gate 1 — manifest
../../tool/check_release_manifest.sh build/app-release-universal.apk

# 4. gate 2 — obfuscation
"$REPO/scripts/mobile/apk_obfuscation_check.sh" \
  build/app-release-universal.apk build/symbols android/app/build.gradle.kts

# 5. gate 3 — secrets
"$REPO/scripts/mobile/apk_secret_scan.sh" build/app-release-universal.apk "$REPO/.env.example"

# 6. gate 4 — MobSF, locally, on the same APK
docker run -d --name mobsf -p 8000:8000 -e MOBSF_API_KEY=local \
  opensecurity/mobile-security-framework-mobsf:latest
until curl -sf http://localhost:8000/api/v1/scans -H "Authorization: local" >/dev/null; do sleep 3; done
hash=$(curl -sf -F "file=@build/app-release-universal.apk" \
  http://localhost:8000/api/v1/upload -H "Authorization: local" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["hash"])')
curl -sf -X POST http://localhost:8000/api/v1/scan -H "Authorization: local" -d "hash=$hash" >/dev/null
curl -sf -X POST http://localhost:8000/api/v1/report_json -H "Authorization: local" -d "hash=$hash" > mobsf-report.json
python3 "$REPO/scripts/mobile/mobsf_gate.py" mobsf-report.json
docker rm -f mobsf
```

`$REPO` is the repository root. The MobSF web UI on <http://localhost:8000> renders the same
report far more readably than the JSON — use it for triage, the JSON for the gate.

Requirements: JDK 17 (`setup-java` in CI), the Android SDK with build-tools and cmdline-tools
on `$ANDROID_HOME`, docker for gate 4.

### Triage

1. **Gate 1 or 2 fires** — almost always a build-configuration regression, not an attack.
   Check `android/app/build.gradle.kts` (`isDebuggable`, `isMinifyEnabled`,
   `isShrinkResources`, the `release` signing config) and that the build command still carries
   `--obfuscate --split-debug-info`. `apps/mobile/tool/build_release.sh` is the reference build;
   if CI diverges from it, fix CI. Never relax the gate to get a release out.

2. **Gate 3 fires with a `env-value:` pattern** — treat the value as compromised until proven
   otherwise. Do not print it. Find where it entered the app (`grep -rn` the *name*, not the
   value, across `apps/mobile`; check `--dart-define`, `config/env/*.json` and any asset added
   in the release). If it is a real credential that reached a built artefact, this is a
   **sev 1**: go to [suspected data breach](suspected-data-breach.md), rotate the credential
   first, investigate second. If it is a placeholder the filter should have caught, widen
   `PLACEHOLDER` in the script — not the ignore list.

3. **Gate 3 fires with a known-shape pattern** — identify the entry. A hit in
   `assets/flutter_assets/**` or `classes*.dex` is ours and is a real finding. A hit inside a
   third-party `.so` or a font/ML asset is usually a byte sequence that happens to match; only
   then consider `SECRET_SCAN_IGNORE_ENTRIES`, scoped to that exact entry, documented here.

4. **Gate 4 fires** — open the report (web UI or artefact), find the finding by section and
   rule, and decide: fix it, or accept it. Most MobSF "high" findings on a Flutter app are
   about the Java/Kotlin shim or a plugin, and are genuinely fixable.

### Recording an accepted finding

MobSF findings are not silenced in the tool; we do not carry a suppression file. An accepted
finding is recorded once, in the open:

1. Open an ADR in `docs/adr/` when the acceptance is architectural, or a tracking issue when it
   is temporary. Record: the rule id and section, the exact finding text, why it is not
   exploitable in our app, what would make it exploitable, and a review date.
2. If it must stop blocking releases, raise `MOBSF_HIGH_LIMIT` in
   `.github/workflows/mobile-release.yml` **by the number of accepted findings**, in the same PR
   that links the ADR or issue, with the reason in the PR body. Never set it high "for now".
3. The security owner approves the PR. Re-review at the recorded date; the limit goes back down
   when the finding is fixed.
4. `secrets` findings are **never** accepted this way. There is no limit to raise — a secret in
   the APK is fixed or the release does not ship.

## Human gates that remain

The pipeline stops short of anything that puts a build in front of a user (CLAUDE.md:
publishing to Play Console is human-only, SPEC 14.6):

- **Release signing.** The upload keystore lives in Secret Manager in `farmerapp-ops` and is
  fetched over WIF, used, and deleted by the `Remove signing material` step. No key material in
  GitHub (SEC-010). Creating or rotating the key is a human action.
- **Play Console promotion.** CI uploads to the **internal** track only. Promotion to closed
  testing and to production is a human decision in Play Console, with the release notes, the
  staged-rollout percentage and the rollout halt all under human control.
- **Accepting a finding** — the security owner, per the section above.
- **`vars.MOBSF_OPTIONAL`** — setting it is a human decision with an issue attached, and the
  variable is expected to be unset in steady state.

See also: [bad mobile release rollback](bad-mobile-release-rollback.md) for what to do once a
bad build is already on the internal track.
