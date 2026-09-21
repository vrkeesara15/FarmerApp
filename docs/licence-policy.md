# Licence policy (SEC-007)

Owner: engineering lead. Gate: `licence compliance, no AGPL in shipped apps (SEC-007)` in
[`.github/workflows/security.yml`](../.github/workflows/security.yml), on every PR, every push
to `main` and nightly. A failing gate blocks merge (SPEC 11.1).

SPEC 11.1 states the requirement as "License compliance (no AGPL in shipped apps)". This
document says what "shipped" means for each of our three artefacts, which licences are allowed
and denied, how the three ecosystems are scanned, and how to add an exception.

- Policy data: [`scripts/licences/allowlist.toml`](../scripts/licences/allowlist.toml)
- Gate: [`scripts/licences/check_licences.py`](../scripts/licences/check_licences.py)

## What "shipped" means

| Artefact | What leaves our control | Dependency set the gate scans |
|---|---|---|
| **API / worker / jobs container image** (`apps/api/Dockerfile`) | Nothing. The image runs on Cloud Run; users interact with it over HTTPS. It is *never conveyed* to a third party. | `uv export --frozen --no-dev` — the same set `uv sync --frozen --no-dev` installs into `/opt/venv`. pytest, ruff, mypy, bandit and the rest of the `dev` group are excluded. |
| **Console bundle** (`apps/console/Dockerfile`) | The browser bundle is conveyed to every user who loads the console. The image itself is not. | `license-checker-rseidelsohn --production` — `dependencies`, not `devDependencies`. |
| **Flutter apps** (`agent`, `farmer`) | Fully conveyed: an APK/AAB installed on a farmer's phone, statically linked and AOT-compiled. This is the strictest artefact. | every `pubspec.lock` under `apps/mobile`, minus `dependency: direct dev` entries and first-party `source: path` packages. |

Because copyleft obligations attach to *conveying* a work, the mobile apps carry the most risk
and the API image the least. The gate applies one policy to all three and records the
artefact-specific reasoning in each exception, rather than maintaining three allowlists.

### Known gaps

- **Dart dev transitives.** `pubspec.lock` marks a package `direct main`, `direct dev` or
  `transitive`. A package pulled in only by a dev dependency is still marked `transitive`, so
  it cannot be told apart from a shipped one. The gate therefore scans dev transitives too:
  it over-reports rather than under-reports. `build_runner`'s tree is the main source of noise.
- **Node optional platform packages.** `@img/sharp-*` resolves differently on a macOS laptop
  (`darwin-arm64`) and on ubuntu CI (`linux-x64`), so exceptions for them use globs.
- **Python platform markers.** A couple of packages in `uv.lock` (`colorama`, the Pyodide httpx
  transport) have environment markers that never match Linux or macOS, so they are never
  installed and cannot be scanned. The run prints them as a note.

<a id="denied"></a>
## Denied

These fail the build for every artefact.

- **AGPL-1.0 / AGPL-3.0, any variant.** The headline ban in SPEC 11.1. §13 of AGPL-3.0 makes
  *network interaction* with a modified version a trigger for source disclosure — the one
  copyleft licence whose obligations reach a hosted service that conveys nothing. Our API is
  exactly such a service, so AGPL is unusable for us even where GPL would be merely awkward.
- **SSPL-1.0** for the same reason, more aggressively: it reaches the whole service stack.
- **GPL-2.0 / GPL-3.0, any variant.** Strong copyleft over the combined work. The Flutter apps
  statically link everything into one AOT binary, so any GPL dependency would relicense the
  app. Denied everywhere for consistency rather than per artefact.
- **LGPL-2.0 / 2.1 / 3.0** — see below, denied by default and allowed only per package.
- **BUSL-1.1, Commons Clause, EUPL-1.2, OSL-3.0** — source-available or
  strongly-reciprocal-and-incompatible; not open source we can ship.
- **CC-BY-SA / CC-BY-NC** — share-alike or non-commercial; we are a commercial product.
- **UNLICENSED** — npm's marker for a proprietary package. (The workspace root itself is
  `private: true` and marked `UNLICENSED`; the gate skips it, since it is our own code.)

`denied_prefixes` additionally catches any new spelling starting `AGPL`, `SSPL`, `CC-BY-NC`,
`Commons-Clause` or `Business-Source`, so an unfamiliar variant fails rather than falling
through to `unknown`.

<a id="lgpl"></a>
## LGPL: denied by default, allowed per package

LGPL's obligations depend entirely on *how* the library is linked, which no allowlist entry can
express in the abstract. So LGPL sits on the `denied` list and a package is admitted only
through an exception carrying `overrides_denied = true` and a written reason.

- **Dynamically linked, unmodified** (a Python import from `site-packages`, a `.so` loaded by a
  Node addon): LGPL-3.0 §4 is satisfiable — the recipient can replace the library and relink.
  Admissible for the API image and the console image.
- **Statically linked** (a Flutter AOT snapshot, an R8-merged DEX): §4 would require us to ship
  object files or an equivalent relinking mechanism. **Never accept an LGPL package in
  `apps/mobile`.**
- **Modified in any way** (vendored, patched, forked in-tree): the exception is void and the
  full LGPL source-disclosure obligation applies. Do not do this.

Current LGPL exceptions: `fpdf2` (python, PDF rendering in the API) and `@img/sharp-libvips-*`
(node, Next.js image optimisation). Both are unmodified and dynamically linked; neither is in
a conveyed artefact.

<a id="weak-copyleft"></a>
## Weak copyleft: allowed

**MPL-2.0**, **EPL-2.0** and **CDDL-1.0** reciprocate at *file* granularity: the obligation is
to publish changes to the licensed files themselves, not to the work that uses them. We never
modify upstream sources in place — a change goes upstream as a PR, or we fork and the fork
becomes a first-party package with its own licence. So these are allowed for all three
artefacts, including the Flutter apps.

MPL-2.0 has one trap worth knowing: its "Secondary License" definition *names* the GPL, LGPL
and AGPL in the body of the licence text. A naive whole-file text search flags every MPL-2.0
package as AGPL. The dart scanner therefore matches copyleft licences by their **title block**
(the first twelve non-empty lines) and permissive ones by their distinctive grant sentence.
`dbus`, `geoclue`, `gsettings`, `nm` and `upower` are MPL-2.0 packages in our tree that a
whole-text matcher gets wrong.

## Allowed

`MIT`, `MIT-0`, `MIT-CMU`, `BSD-2-Clause`, `BSD-3-Clause`, `0BSD`, `Apache-2.0`, `ISC`,
`PSF-2.0`, `Python-2.0`, `Unlicense`, `CC0-1.0`, `Zlib`, `NCSA`, `Artistic-2.0`,
`BlueOak-1.0.0`, `Unicode-3.0`, `MPL-2.0`, `EPL-2.0`, `CDDL-1.0`. The authoritative list is
`allowed` in `allowlist.toml`; this paragraph is a summary.

`LicenseRef-FlutterSDK` covers `source: sdk` entries in `pubspec.lock` (`flutter`, `sky_engine`,
…). They are the Flutter SDK, BSD-3-Clause, and have no pub cache directory to read a LICENSE
from; the engine's own third-party notices are compiled into the app and shown by Flutter's
`LicenseRegistry`.

## How licence expressions are judged

Reported strings are normalised to SPDX ids through the `[aliases]` table (pip reports Trove
classifier names like `Apache Software License`; npm mostly reports SPDX; pub.dev reports
nothing at all). Then:

- `A OR B` — we may pick either, so it passes if **any** branch is fully allowed.
  `MIT OR AGPL-3.0` passes; we take the MIT grant.
- `A AND B` — both bind, so **every** atom must be allowed.
- `A WITH <exception>` — judged on the base licence.
- Anything left unrecognised is `unknown` and fails unless an exception covers it. A licence we
  cannot name is not a licence we can ship.

<a id="exceptions"></a>
## Adding an exception

An exception is a claim that a specific package, at a specific reported licence, is safe in the
artefact that ships it. It is reviewed by the **engineering lead** and re-reviewed yearly.

1. Prefer removing or replacing the dependency. An exception is the last option, not the first.
2. Read the package's actual LICENSE file — not the metadata, not the README badge.
3. Add a `[[exceptions]]` block to `scripts/licences/allowlist.toml`:

   ```toml
   [[exceptions]]
   package = "some-package"        # exact name, or an fnmatch glob for platform variants
   ecosystem = "python"            # python | node | dart | *
   licence = "LGPL-3.0-only"       # AS REPORTED by the tooling, or "*"
   overrides_denied = true         # required when the licence is on the denied list
   reason = """Why this is safe for the artefact that ships it: how it is linked,
   whether that artefact is conveyed, and what would void the exception."""
   reviewed_on = "2026-09-19"
   ```

4. `reason` must answer three questions: **which artefact ships it**, **how it is linked**, and
   **what would make the exception invalid** (typically: modifying or vendoring the package).
   "Transitive dependency, can't remove it" is not a reason.
5. Pin `licence` to the reported value rather than `"*"` wherever possible. If upstream
   relicenses, the exception stops matching and the gate fires again — that is the point.
6. `overrides_denied` is required for a denied licence and is the flag a reviewer looks for. An
   exception without it will not admit a denied package; the gate says so explicitly.
7. Mention the exception in the PR description and link this section.

Exceptions are not a place to park `unknown` results you did not investigate. If the gate says
`unknown`, the fix is usually an entry in `[aliases]` (the tool reported a non-SPDX synonym of
a licence we already allow), not an exception.

## Running it locally

```bash
# everything (python + node + dart)
python3 scripts/licences/check_licences.py --ecosystem all

# one ecosystem, only the offending rows, machine-readable report
python3 scripts/licences/check_licences.py --ecosystem node --quiet --json /tmp/lic.json

# offline (no pub.dev lookups); --strict turns an unscannable ecosystem into a failure
python3 scripts/licences/check_licences.py --ecosystem dart --no-network --strict
```

Prerequisites, matching what CI installs:

- python — `uv` on PATH and `cd apps/api && uv sync --frozen`. `pip-licenses` is fetched on
  demand by `uv run --with`; nothing is added to the project. Without `uv` the script falls
  back to a `pip-licenses` on PATH and scans the whole environment (dev dependencies included)
  — it says so in a note.
- node — `npx` and `cd apps/console && npm ci`. The checker itself is fetched by `npx --yes`.
- dart — a populated pub cache: `cd apps/mobile && flutter pub get`. `$PUB_CACHE` is honoured.
  With no cache the script reads the licence from the pub.dev package archive instead; with
  neither cache nor network it skips the ecosystem with a reason, and `--strict` (what CI uses)
  turns that skip into a failure.

The summary line is `licences: <n> packages, <k> exceptions, 0 denied, 0 unknown`. Exit 0 means
clean; exit 1 means a denied or unknown package, or, under `--strict`, an ecosystem that could
not be scanned.

## Baseline

First full run of the gate, 2026-09-19 (macOS, populated pub cache):

| Ecosystem | Packages | Exceptions | Denied | Unknown |
|---|---|---|---|---|
| python (apps/api runtime) | 93 | 1 (`fpdf2`) | 0 | 0 |
| node (apps/console production) | 110 | 2 (`@img/sharp-libvips-*`, `caniuse-lite`) | 0 | 0 |
| dart (apps/mobile) | 224 | 0 | 0 | 0 |
| **all** | **427** | **3** | **0** | **0** |

Counts drift with the lockfiles; the numbers that matter are the last two columns.
