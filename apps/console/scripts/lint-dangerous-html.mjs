#!/usr/bin/env node
/**
 * lint-dangerous-html (SEC-022, "output encoding in console"): fails when a file introduces a
 * new `dangerouslySetInnerHTML` (or a raw `innerHTML =` assignment) outside the allowlist.
 *
 * React escapes everything it renders; `dangerouslySetInnerHTML` is the one hole through which
 * API or user data could reach the DOM as markup, and a nonce-based CSP does not stop injected
 * markup from carrying an `onerror=` handler. The console therefore has exactly two of them —
 * the pre-hydration theme and locale bootstrap scripts in `app/layout.tsx`, whose content is a
 * constant string from our own source and which now carry the CSP nonce.
 *
 * How to allowlist: add an entry to ALLOWED below with the file, the expected number of
 * occurrences and the reason. There is no inline comment escape hatch on purpose — a new one
 * should be a reviewed decision.
 *
 * Usage: node scripts/lint-dangerous-html.mjs [--verbose] [file-or-dir ...]
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SCAN_DIRS = ["app", "components", "lib", "scripts"];
const SKIP_DIRS = new Set(["node_modules", ".next", "playwright-report", "test-results"]);
const SOURCE = /\.(tsx?|jsx?|mjs)$/;

/** file -> { count, reason }. `count` is exact: adding a third occurrence fails too. */
const ALLOWED = {
  "app/layout.tsx": {
    count: 2,
    reason:
      "themeInitScript + localeInitScript: constant strings from components/theme/theme.ts and " +
      "lib/i18n.ts, run before hydration, nonce'd by middleware.ts (SEC-022)",
  },
};

/** This linter and its own test quote the pattern; they are not React output. */
const SELF = new Set(["scripts/lint-dangerous-html.mjs", "scripts/lint-dangerous-html.test.ts"]);

const PATTERNS = [
  { name: "dangerouslySetInnerHTML", re: /dangerouslySetInnerHTML/g },
  { name: "innerHTML assignment", re: /\.innerHTML\s*=/g },
  { name: "outerHTML assignment", re: /\.outerHTML\s*=/g },
  { name: "document.write", re: /document\s*\.\s*write(ln)?\s*\(/g },
];

function walk(dir, out = []) {
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (SKIP_DIRS.has(entry)) continue;
      walk(full, out);
    } else if (SOURCE.test(entry)) out.push(full);
  }
  return out;
}

const argv = process.argv.slice(2);
const verbose = argv.includes("--verbose");
const explicit = argv.filter((a) => !a.startsWith("--")).map((a) => resolve(a));
const targets = explicit.length ? explicit : SCAN_DIRS.map((d) => join(root, d));

const problems = [];
const seen = new Map(); // rel path -> occurrences
let scanned = 0;

for (const target of targets) {
  let files = [];
  try {
    files = statSync(target).isDirectory() ? walk(target) : [target];
  } catch {
    continue;
  }
  for (const file of files) {
    const rel = relative(root, file).split("\\").join("/");
    if (SELF.has(rel)) continue;
    scanned++;
    if (verbose) console.log(`  scanning ${rel}`);
    const src = readFileSync(file, "utf8");
    const lines = src.split("\n");
    for (const { name, re } of PATTERNS) {
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(src))) {
        const line = src.slice(0, m.index).split("\n").length;
        const allowance = ALLOWED[rel];
        const count = (seen.get(rel) ?? 0) + 1;
        seen.set(rel, count);
        if (allowance && count <= allowance.count) continue;
        problems.push(`${rel}:${line}  ${name}: ${(lines[line - 1] ?? "").trim().slice(0, 100)}`);
      }
    }
  }
}

// An allowlisted file that no longer needs its allowance should lose it (only when the whole
// tree was scanned, so targeted runs from the unit test stay quiet).
if (!explicit.length)
  for (const [file, { count }] of Object.entries(ALLOWED)) {
    const found = seen.get(file) ?? 0;
    if (found < count)
      problems.push(
        `${file}  stale allowlist entry: expected ${count} occurrence(s), found ${found} — ` +
          "lower or remove the entry in scripts/lint-dangerous-html.mjs",
      );
  }

if (problems.length) {
  console.error(
    `lint-dangerous-html: ${problems.length} unsafe HTML sink(s) (SEC-022: React escapes output; ` +
      "allowlist in scripts/lint-dangerous-html.mjs):\n",
  );
  for (const p of problems) console.error("  " + p);
  process.exit(1);
}
console.log(
  `lint-dangerous-html: OK (${scanned} files scanned, allowlisted: ${Object.keys(ALLOWED).join(", ") || "none"})`,
);
