#!/usr/bin/env python3
"""SEC-007 — licence compliance gate for everything FarmerApp ships.

SPEC 11.1: "License compliance (no AGPL in shipped apps)".

Collects the licence of every *shipped runtime* dependency of the three
artefacts, normalises it to an SPDX identifier, and fails when a package is
denied (AGPL/SSPL/GPL/…) or when its licence cannot be recognised and no
exception in ``allowlist.toml`` covers it.

    python3 scripts/licences/check_licences.py --ecosystem all
    python3 scripts/licences/check_licences.py --ecosystem python --json report.json

Ecosystems
    python  ``uv export --no-dev`` gives the runtime dependency set of
            apps/api; ``pip-licenses --format=json`` gives licences for the
            synced venv; we report the intersection, so pytest/ruff/mypy and
            friends are excluded from the gate.
    node    ``license-checker-rseidelsohn --production`` inside apps/console
            (``--production`` already drops devDependencies).
    dart    every ``pubspec.lock`` under apps/mobile, resolved against the
            local pub cache; ``direct dev`` entries are dropped (see
            docs/licence-policy.md for the caveat about their transitives).

Stdlib only (Python 3.12): tomllib for the allowlist, subprocess for the
ecosystem tools, urllib for the optional pub.dev fallback.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ALLOWLIST = Path(__file__).resolve().parent / "allowlist.toml"

ECOSYSTEMS = ("python", "node", "dart")

# Verdicts, worst last: the summary counts and the exit code key off these.
OK, EXCEPTED, UNKNOWN, DENIED = "ok", "excepted", "unknown", "denied"


# ---------------------------------------------------------------------------
# model
# ---------------------------------------------------------------------------
@dataclass
class Package:
    name: str
    version: str
    ecosystem: str
    reported: str  # licence exactly as the ecosystem tool reported it
    origin: str = ""  # where we read it from (pub cache path, pub.dev, …)
    spdx: str = ""  # normalised expression
    verdict: str = UNKNOWN
    detail: str = ""


@dataclass
class Result:
    packages: list[Package] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)  # ecosystem: reason

    def extend(self, other: Result) -> None:
        self.packages.extend(other.packages)
        self.skipped.extend(other.skipped)


class GateError(RuntimeError):
    """A tool we need is missing or failed; the gate cannot make a judgement."""


# ---------------------------------------------------------------------------
# allowlist
# ---------------------------------------------------------------------------
class Policy:
    def __init__(self, path: Path) -> None:
        with path.open("rb") as fh:
            raw = tomllib.load(fh)
        self.allowed = {s.lower() for s in raw.get("allowed", [])}
        self.denied = {s.lower() for s in raw.get("denied", [])}
        self.denied_prefixes = tuple(s.lower() for s in raw.get("denied_prefixes", []))
        self.aliases = {k.lower(): v for k, v in raw.get("aliases", {}).items()}
        self.exceptions = list(raw.get("exceptions", []))
        # Canonical casing for display: "mit" -> "MIT".
        self.canonical = {s.lower(): s for s in raw.get("allowed", []) + raw.get("denied", [])}

    # -- licence expression handling ----------------------------------------
    # Only unambiguous separators: a bare "," or "/" appears *inside* real
    # licence names ("Apache License, Version 2.0", "MIT/X11", "zlib/libpng").
    _SPLIT_OR = re.compile(r"\s+OR\s+|\s*\|\s*", re.IGNORECASE)
    _SPLIT_AND = re.compile(r"\s+AND\s+|\s*;\s*", re.IGNORECASE)

    @staticmethod
    def _unwrap(text: str) -> str:
        t = " ".join(text.strip().split())
        while t.startswith("(") and t.endswith(")") and t.count("(") == t.count(")"):
            t = t[1:-1].strip()
        return t

    def _atom(self, text: str) -> str:
        """Normalise a single licence name to an SPDX id (best effort)."""
        t = self._unwrap(text)
        if not t:
            return ""
        # "Apache-2.0 WITH LLVM-exception" -> judge on the base licence.
        if re.search(r"\s+with\s+", t, re.IGNORECASE):
            t = re.split(r"\s+with\s+", t, maxsplit=1, flags=re.IGNORECASE)[0].strip()
        # Candidate spellings, most specific first: as reported, without a
        # trailing "(ABBREV)", and without a trailing "License"/"Licence".
        cands = [t.lower()]
        cands.append(re.sub(r"\s*\([^()]*\)$", "", cands[0]).strip())
        cands += [re.sub(r"\s+licen[cs]e$", "", c).strip() for c in list(cands)]
        for c in cands:
            if not c:
                continue
            if c in self.aliases:
                mapped = self.aliases[c]
                return "" if mapped == "__drop__" else mapped
            if c in self.canonical:
                return self.canonical[c]
        return t

    def _atom_verdict(self, atom: str) -> str:
        low = atom.lower()
        if low in self.denied or low.startswith(self.denied_prefixes):
            return DENIED
        if low in self.allowed:
            return OK
        return UNKNOWN

    def evaluate(self, reported: str) -> tuple[str, str, str]:
        """-> (spdx expression, verdict, detail)."""
        text = self._unwrap(reported or "")
        if not text or text.upper() in {"UNKNOWN", "NONE", "NOASSERTION", "N/A"}:
            return ("UNKNOWN", UNKNOWN, "no licence metadata")

        alternatives: list[list[str]] = []
        for alt in self._SPLIT_OR.split(text):
            atoms = [a for a in (self._atom(x) for x in self._SPLIT_AND.split(alt)) if a]
            if atoms:
                alternatives.append(atoms)
        if not alternatives:
            return ("UNKNOWN", UNKNOWN, "no licence metadata")

        spdx = " OR ".join(" AND ".join(alt) for alt in alternatives)
        all_atoms = [a for alt in alternatives for a in alt]

        # An OR gives us the choice: one fully-allowed branch is enough.
        for alt in alternatives:
            if all(self._atom_verdict(a) == OK for a in alt):
                return (spdx, OK, "")
        denied = [a for a in all_atoms if self._atom_verdict(a) == DENIED]
        if denied and len(alternatives) == 1:
            return (spdx, DENIED, "denied: " + ", ".join(sorted(set(denied))))
        if denied and all(
            any(self._atom_verdict(a) == DENIED for a in alt) for alt in alternatives
        ):
            return (spdx, DENIED, "every alternative is denied: " + ", ".join(sorted(set(denied))))
        unrec = [a for a in all_atoms if self._atom_verdict(a) == UNKNOWN]
        return (spdx, UNKNOWN, "unrecognised: " + ", ".join(sorted(set(unrec))))

    # -- exceptions ----------------------------------------------------------
    def exception_for(self, pkg: Package) -> dict | None:
        for exc in self.exceptions:
            eco = str(exc.get("ecosystem", "*"))
            if eco not in ("*", pkg.ecosystem):
                continue
            if not fnmatch.fnmatch(pkg.name, str(exc.get("package", ""))):
                continue
            want = str(exc.get("licence", "*")).strip()
            if want != "*" and want.lower() not in (
                pkg.reported.strip().lower(),
                pkg.spdx.strip().lower(),
            ):
                continue
            return exc
        return None


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def run(cmd: list[str], cwd: Path, what: str, timeout: int = 900) -> str:
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False
        )
    except FileNotFoundError as exc:
        raise GateError(f"{what}: {cmd[0]} not found on PATH") from exc
    except subprocess.TimeoutExpired as exc:
        raise GateError(f"{what}: timed out after {timeout}s") from exc
    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()[-8:]
        raise GateError(f"{what}: exit {proc.returncode}\n  " + "\n  ".join(tail))
    return proc.stdout


def pep503(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).strip().lower()


# ---------------------------------------------------------------------------
# python (apps/api)
# ---------------------------------------------------------------------------
def collect_python(root: Path) -> Result:
    api = root / "apps" / "api"
    if not (api / "pyproject.toml").exists():
        return Result(skipped=["python: apps/api/pyproject.toml not found"])

    have_uv = shutil.which("uv") is not None

    # 1. the shipped runtime set (everything the container installs).
    runtime: set[str] | None = None
    if have_uv:
        out = run(
            ["uv", "export", "--frozen", "--no-dev", "--no-emit-project", "--no-hashes"],
            api,
            "uv export",
        )
        runtime = {pep503(m.group(1)) for m in re.finditer(r"^([A-Za-z0-9._-]+)==", out, re.M)}

    # 2. licences for everything installed in the environment.
    if have_uv:
        raw = run(
            ["uv", "run", "--frozen", "--with", "pip-licenses", "pip-licenses", "--format=json"],
            api,
            "pip-licenses (uv run)",
        )
    elif shutil.which("pip-licenses"):
        raw = run(["pip-licenses", "--format=json"], api, "pip-licenses")
    else:
        raise GateError(
            "python: neither `uv` nor `pip-licenses` is available; "
            "install uv (https://docs.astral.sh/uv/) or `pip install pip-licenses`"
        )
    # `uv run --with` prints an install line on stderr, but be defensive.
    raw = raw[raw.index("[") :] if "[" in raw else raw
    entries = json.loads(raw)

    packages: list[Package] = []
    seen: set[str] = set()
    for e in entries:
        key = pep503(e.get("Name", ""))
        if runtime is not None and key not in runtime:
            continue  # dev/test-only dependency: not shipped.
        if key in {"farmerapp", ""}:
            continue  # first-party.
        seen.add(key)
        packages.append(
            Package(
                name=e.get("Name", ""),
                version=e.get("Version", ""),
                ecosystem="python",
                reported=str(e.get("License", "") or "UNKNOWN"),
                origin="pip-licenses",
            )
        )

    skipped: list[str] = []
    if runtime is not None:
        missing = sorted(runtime - seen - {"farmerapp"})
        if missing:
            # Platform-conditional wheels (Windows-only colorama, the Pyodide
            # httpx transport) are in uv.lock but never installed on Linux/macOS.
            skipped.append(
                f"python: {len(missing)} locked package(s) not installed in this "
                f"environment (platform-conditional markers): {', '.join(missing)}"
            )
    else:
        skipped.append("python: uv not available, scanned the whole env (dev deps included)")
    return Result(packages=packages, skipped=skipped)


# ---------------------------------------------------------------------------
# node (apps/console)
# ---------------------------------------------------------------------------
def collect_node(root: Path) -> Result:
    console = root / "apps" / "console"
    if not (console / "package.json").exists():
        return Result(skipped=["node: apps/console/package.json not found"])
    if not shutil.which("npx"):
        raise GateError("node: npx not found on PATH (install Node.js 22+)")

    pkg = json.loads((console / "package.json").read_text())
    self_id = f"{pkg.get('name')}@{pkg.get('version')}"

    raw = ""
    errors = []
    for tool in ("license-checker-rseidelsohn", "license-checker"):
        try:
            raw = run(
                ["npx", "--yes", tool, "--production", "--json", "--start", str(console)],
                console,
                f"{tool}",
            )
            break
        except GateError as exc:
            errors.append(str(exc))
    if not raw:
        raise GateError("node: no licence checker could run\n" + "\n".join(errors))

    raw = raw[raw.index("{") :] if "{" in raw else raw
    entries = json.loads(raw)

    packages: list[Package] = []
    for key, meta in entries.items():
        if key == self_id:
            continue  # the private workspace root itself.
        name, _, version = key.rpartition("@")
        lic = meta.get("licenses", "UNKNOWN")
        if isinstance(lic, list):
            lic = " AND ".join(str(x) for x in lic)
        packages.append(
            Package(
                name=name or key,
                version=version,
                ecosystem="node",
                reported=str(lic or "UNKNOWN").replace("*", ""),  # "MIT*" = guessed from a file
                origin="license-checker",
            )
        )
    return Result(packages=packages)


# ---------------------------------------------------------------------------
# dart (apps/mobile)
# ---------------------------------------------------------------------------
# (spdx, markers, head_only). Ordered: the first match wins.
#
# `head_only` markers are matched against the licence *title block* (the first
# few non-empty lines) only. This matters: the body of MPL-2.0 names the GPL,
# the LGPL and the AGPL in its "Secondary License" definition, so a whole-text
# search flags every MPL-2.0 package as AGPL. Identifying a copyleft licence by
# its title and a permissive one by its distinctive grant sentence is what the
# SPDX matching guideline itself recommends.
LICENCE_MARKERS: list[tuple[str, tuple[str, ...], bool]] = [
    ("MPL-2.0", ("mozilla public license version 2.0", "mozilla public license, v. 2.0",
                 "mozilla public license 2.0"), True),
    ("AGPL-3.0-only", ("gnu affero general public license",), True),
    ("LGPL-3.0-only", ("gnu lesser general public license version 3",), True),
    ("LGPL-2.1-only", ("gnu lesser general public license",), True),
    ("GPL-3.0-only", ("gnu general public license version 3",), True),
    ("GPL-2.0-only", ("gnu general public license",), True),
    ("Apache-2.0", ("apache license version 2.0", "apache license, version 2.0"), True),
    ("EPL-2.0", ("eclipse public license - v 2.0",), True),
    ("CC0-1.0", ("cc0 1.0 universal",), True),
    ("Unlicense", ("this is free and unencumbered software released into the public domain",),
     False),
    ("ISC", ("permission to use, copy, modify, and/or distribute this software",), False),
    ("Zlib", ("altered source versions must be plainly marked as such",), False),
    ("MIT", ("permission is hereby granted, free of charge",), False),
    ("BSD-3-Clause", ("neither the name of", "names of its contributors may be used"), False),
    ("BSD-2-Clause", ("redistribution and use in source and binary forms",), False),
]
# How much of the file counts as the title block. MPL-2.0 first names the AGPL
# at roughly 2.7 kB in; twelve lines is comfortably before that and still after
# any leading copyright header.
HEAD_LINES = 12


def _licence_from_text(text: str) -> str:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    head = " ".join(" ".join(lines[:HEAD_LINES]).lower().split())
    body = " ".join(text.lower().split())
    for spdx, markers, head_only in LICENCE_MARKERS:
        haystack = head if head_only else body
        if any(marker in haystack for marker in markers):
            return spdx
    return ""


def _pub_cache_dirs() -> list[Path]:
    roots = []
    if os.environ.get("PUB_CACHE"):
        roots.append(Path(os.environ["PUB_CACHE"]))
    roots += [Path.home() / ".pub-cache", Path.home() / "AppData" / "Local" / "Pub" / "Cache"]
    out = []
    for r in roots:
        hosted = r / "hosted"
        if hosted.is_dir():
            out.extend(p for p in hosted.iterdir() if p.is_dir())
    return out


def _read_lockfile(path: Path) -> list[tuple[str, str, str, str]]:
    """Minimal pubspec.lock reader -> [(name, version, source, dependency)].

    pubspec.lock is YAML, but its shape is fixed and we may not import PyYAML,
    so a line reader is both sufficient and dependency-free.
    """
    out: list[tuple[str, str, str, str]] = []
    name = dep = source = version = ""
    in_packages = False
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            in_packages = line.startswith("packages:")
            continue
        if not in_packages:
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 2 and stripped.endswith(":"):
            if name:
                out.append((name, version, source, dep))
            name, dep, source, version = stripped[:-1].strip('"'), "", "", ""
        elif indent == 4:
            key, _, value = stripped.partition(":")
            value = value.strip().strip('"')
            if key == "dependency":
                dep = value
            elif key == "source":
                source = value
            elif key == "version":
                version = value
    if name:
        out.append((name, version, source, dep))
    return out


def _get(url: str, timeout: float) -> bytes:
    if not url.startswith("https://pub.dev/"):  # never follow an arbitrary host
        raise urllib.error.URLError(f"refusing non-pub.dev URL {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "farmerapp-licence-gate"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read(MAX_ARCHIVE_BYTES + 1)


MAX_ARCHIVE_BYTES = 32 * 1024 * 1024


def _pubdev_licence(name: str, version: str, timeout: float) -> tuple[str, str]:
    """Resolve a licence from pub.dev when the local pub cache has no copy.

    pubspec.yaml has no `license` field in practice, so this normally falls
    through to downloading the package archive and reading its LICENSE — the
    same file the cache would have held.
    """
    meta = json.loads(_get(f"https://pub.dev/api/packages/{name}/versions/{version}", timeout))
    declared = str((meta.get("pubspec") or {}).get("license") or "").strip()
    if declared:
        return (declared, "pub.dev pubspec")

    archive = str(meta.get("archive_url") or "")
    if not archive:
        return ("", "pub.dev (no archive)")
    blob = _get(archive, timeout)
    if len(blob) > MAX_ARCHIVE_BYTES:
        return ("", "pub.dev (archive too large)")

    import io
    import tarfile

    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
        for member in tar.getmembers():
            base = Path(member.name).name
            if member.isfile() and base in {"LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING"}:
                fh = tar.extractfile(member)
                if fh is None:
                    continue
                text = fh.read(512 * 1024).decode("utf-8", "replace")
                return (_licence_from_text(text), f"pub.dev archive {base}")
    return ("", "pub.dev (no LICENSE in archive)")


def collect_dart(root: Path, allow_network: bool) -> Result:
    mobile = root / "apps" / "mobile"
    locks = sorted(mobile.rglob("pubspec.lock")) if mobile.is_dir() else []
    if not locks:
        return Result(skipped=["dart: no pubspec.lock under apps/mobile"])

    resolved: dict[tuple[str, str], tuple[str, str, str]] = {}
    for lock in locks:
        for name, version, source, dep in _read_lockfile(lock):
            if source == "path":
                continue  # first-party workspace package.
            if dep == "direct dev":
                continue  # not shipped.
            resolved.setdefault((name, version), (source, dep, str(lock.relative_to(root))))

    caches = _pub_cache_dirs()
    network_note = ""
    packages: list[Package] = []
    for (name, version), (source, _dep, _lock) in sorted(resolved.items()):
        if source == "sdk":
            # Shipped with the Flutter SDK, not from pub.dev, so there is no
            # cache entry to read. See `LicenseRef-FlutterSDK` in allowlist.toml.
            packages.append(
                Package(
                    name,
                    version,
                    "dart",
                    "LicenseRef-FlutterSDK",
                    origin="flutter sdk (no pub cache entry)",
                )
            )
            continue
        text = ""
        origin = ""
        for cache in caches:
            pkg_dir = cache / f"{name}-{version}"
            for fname in ("LICENSE", "LICENSE.md", "LICENSE.txt", "license", "COPYING"):
                f = pkg_dir / fname
                if f.is_file():
                    text = f.read_text(errors="replace")
                    origin = str(f)
                    break
            if text:
                break
        spdx = _licence_from_text(text) if text else ""
        if not spdx and allow_network:
            try:
                spdx, origin = _pubdev_licence(name, version, timeout=20)
            except Exception as exc:
                network_note = f"pub.dev lookup for {name} failed ({type(exc).__name__})"
        packages.append(
            Package(
                name=name,
                version=version,
                ecosystem="dart",
                reported=spdx or "UNKNOWN",
                origin=origin or ("pub cache miss" if caches else "no pub cache"),
            )
        )

    # SDK entries resolve without a cache, so they do not count as evidence
    # that licence resolution is working at all.
    resolved_any = any(
        p.reported not in ("UNKNOWN", "", "LicenseRef-FlutterSDK") for p in packages
    )
    if not caches and not resolved_any:
        # Neither the pub cache nor pub.dev could tell us anything, so every
        # package would be reported `unknown` and the run would say nothing
        # useful about the code. Raise: the caller skips this ecosystem with a
        # reason, or fails the build under --strict.
        raise GateError(
            "no pub cache under $PUB_CACHE or ~/.pub-cache and "
            + ("pub.dev is unreachable" if allow_network else "--no-network was passed")
            + f"; run `flutter pub get` in {mobile.relative_to(root)} first"
        )

    skipped: list[str] = []
    if not caches:
        skipped.append("dart: no pub cache found; licences came from the pub.dev API")
    if network_note:
        skipped.append("dart: " + network_note)
    return Result(packages=packages, skipped=skipped)


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------
def judge(packages: list[Package], policy: Policy) -> None:
    for p in packages:
        p.spdx, p.verdict, p.detail = policy.evaluate(p.reported)
        if p.verdict in (DENIED, UNKNOWN):
            exc = policy.exception_for(p)
            if exc is None:
                continue
            if p.verdict == DENIED and not exc.get("overrides_denied", False):
                p.detail += " (exception found but it does not set overrides_denied)"
                continue
            p.verdict = EXCEPTED
            p.detail = f"exception, reviewed {exc.get('reviewed_on', '?')}"


def print_table(packages: list[Package]) -> None:
    if not packages:
        return
    rows = [("PACKAGE", "VERSION", "ECO", "LICENCE", "VERDICT")]
    rows += [
        (p.name[:44], p.version[:14], p.ecosystem, (p.spdx or p.reported)[:38], p.verdict)
        for p in packages
    ]
    widths = [max(len(r[i]) for r in rows) for i in range(5)]
    for i, row in enumerate(rows):
        print("  ".join(c.ljust(w) for c, w in zip(row, widths, strict=True)).rstrip())
        if i == 0:
            print("  ".join("-" * w for w in widths))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--ecosystem", default="all", choices=[*ECOSYSTEMS, "all"])
    ap.add_argument("--allowlist", type=Path, default=ALLOWLIST)
    ap.add_argument("--root", type=Path, default=REPO_ROOT)
    ap.add_argument("--json", type=Path, help="write a machine-readable report here")
    ap.add_argument(
        "--strict",
        action="store_true",
        help="an ecosystem that cannot be scanned (missing tool, no pub cache) "
        "fails instead of being skipped",
    )
    ap.add_argument("--no-network", action="store_true", help="never call the pub.dev API")
    ap.add_argument("--quiet", action="store_true", help="only print offending packages")
    args = ap.parse_args(argv)

    policy = Policy(args.allowlist)
    wanted = ECOSYSTEMS if args.ecosystem == "all" else (args.ecosystem,)

    result = Result()
    hard_errors: list[str] = []
    for eco in wanted:
        try:
            if eco == "python":
                result.extend(collect_python(args.root))
            elif eco == "node":
                result.extend(collect_node(args.root))
            else:
                result.extend(collect_dart(args.root, allow_network=not args.no_network))
        except GateError as exc:
            # A missing toolchain is a skip by default and a failure under --strict:
            # a licence gate that silently scans nothing is worse than no gate.
            (hard_errors if args.strict else result.skipped).append(f"{eco}: {exc}")

    judge(result.packages, policy)
    result.packages.sort(key=lambda p: (p.ecosystem, p.name.lower()))

    offenders = [p for p in result.packages if p.verdict in (DENIED, UNKNOWN)]
    if args.quiet:
        print_table(offenders)
    else:
        print_table(result.packages)

    for note in result.skipped:
        print(f"note: {note}")
    for err in hard_errors:
        print(f"::error::{err}")

    n = len(result.packages)
    k = sum(1 for p in result.packages if p.verdict == EXCEPTED)
    denied = [p for p in result.packages if p.verdict == DENIED]
    unknown = [p for p in result.packages if p.verdict == UNKNOWN]

    if offenders:
        where = args.allowlist
        if where.is_relative_to(args.root):
            where = where.relative_to(args.root)
        print()
        for p in offenders:
            print(
                f"::error::{p.ecosystem} {p.name}@{p.version}: {p.verdict} — "
                f"reported '{p.reported}' — {p.detail}"
            )
        print(
            "\nFix: remove the dependency, replace it, or add a reviewed entry to "
            f"{where} (docs/licence-policy.md#exceptions)."
        )

    print(
        f"\nlicences: {n} packages, {k} exceptions, "
        f"{len(denied)} denied, {len(unknown)} unknown"
    )

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(
                {
                    "ecosystems": list(wanted),
                    "summary": {
                        "packages": n,
                        "exceptions": k,
                        "denied": len(denied),
                        "unknown": len(unknown),
                    },
                    "skipped": result.skipped,
                    "errors": hard_errors,
                    "packages": [vars(p) for p in result.packages],
                },
                indent=2,
                sort_keys=True,
            )
            + "\n"
        )
        print(f"report: {args.json}")

    return 1 if (offenders or hard_errors) else 0


if __name__ == "__main__":
    sys.exit(main())
