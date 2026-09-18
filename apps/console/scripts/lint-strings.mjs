#!/usr/bin/env node
/**
 * lint-strings: fails when JSX contains user-facing string literals that are not
 * routed through `t()` / `useT()` from lib/i18n.ts (CLAUDE.md: "Strings go in i18n files, never hard-coded").
 *
 * What it flags
 *   - JSX text children containing letters:      <p>Hello</p>
 *   - String literals in user-facing attributes:  placeholder="Search" title="..." aria-label="..." alt="..."
 *     (attribute list: TEXT_ATTRS below)
 *
 * How to allowlist
 *   1. Add an i18n-ignore marker on the line before or the same line, as a JSX comment
 *      ({ /* i18n-ignore * / } without the spaces) or a line comment (// i18n-ignore).
 *   2. Add a glob-ish path prefix to ALLOW_PATHS below (gallery + tests + shadcn primitives are allowed).
 *   3. Punctuation-only / numeric text (e.g. "+91", "—", "%") is never flagged.
 *
 * Usage: node scripts/lint-strings.mjs [--verbose] [file-or-dir ...]
 *   Without paths the app/, components/ and lib/ trees are scanned; with paths only those
 *   files or directories are (used by scripts/lint-strings.test.ts on fixtures).
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SCAN_DIRS = ["app", "components", "lib"];
const ALLOW_PATHS = ["app/design/", "components/ui/", "e2e/"];
const ALLOW_FILE = /\.(test|spec|stories)\.tsx?$/;
const TEXT_ATTRS = new Set([
  "placeholder",
  "title",
  "aria-label",
  "alt",
  "label",
  "aria-description",
]);
const argv = process.argv.slice(2);
const verbose = argv.includes("--verbose");
const explicitTargets = argv.filter((a) => !a.startsWith("--")).map((a) => resolve(a));

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (entry === "node_modules" || entry === ".next") continue;
      walk(full, out);
    } else if (/\.tsx$/.test(entry)) out.push(full);
  }
  return out;
}

const hasLetters = (s) => /\p{L}/u.test(s);

function hasIgnoreComment(sf, node) {
  const text = sf.getFullText();
  const start = node.getFullStart();
  const line = sf.getLineAndCharacterOfPosition(node.getStart(sf)).line;
  // Same-line or previous-line ignore marker.
  const lineStarts = sf.getLineStarts();
  const from = lineStarts[Math.max(0, line - 1)] ?? 0;
  const to = lineStarts[line + 1] ?? text.length;
  const window = text.slice(Math.min(from, start), to);
  return /i18n-ignore/.test(window);
}

const problems = [];
let scanned = 0;

const targets = explicitTargets.length ? explicitTargets : SCAN_DIRS.map((d) => join(root, d));

for (const target of targets) {
  let files = [];
  try {
    files = statSync(target).isDirectory() ? walk(target) : [target];
  } catch {
    continue;
  }
  for (const file of files) {
    const rel = relative(root, file).split("\\").join("/");
    if (ALLOW_PATHS.some((p) => rel.startsWith(p)) || ALLOW_FILE.test(rel)) continue;
    scanned++;
    if (verbose) console.log(`  scanning ${rel}`);
    const src = readFileSync(file, "utf8");
    const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);

    const report = (node, kind, value) => {
      if (hasIgnoreComment(sf, node)) return;
      const { line, character } = sf.getLineAndCharacterOfPosition(node.getStart(sf));
      problems.push(
        `${rel}:${line + 1}:${character + 1}  ${kind}: ${JSON.stringify(value.trim())}`,
      );
    };

    const visit = (node) => {
      if (ts.isJsxText(node)) {
        const value = node.getText(sf);
        if (hasLetters(value)) report(node, "raw JSX text", value);
      } else if (ts.isJsxAttribute(node) && node.initializer) {
        const name = node.name.getText(sf);
        if (TEXT_ATTRS.has(name)) {
          const init = node.initializer;
          if (ts.isStringLiteral(init) && hasLetters(init.text))
            report(node, `raw ${name}`, init.text);
          else if (
            ts.isJsxExpression(init) &&
            init.expression &&
            (ts.isStringLiteral(init.expression) ||
              ts.isNoSubstitutionTemplateLiteral(init.expression)) &&
            hasLetters(init.expression.text)
          )
            report(node, `raw ${name}`, init.expression.text);
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(sf);
  }
}

if (problems.length) {
  console.error(
    `lint-strings: ${problems.length} hard-coded UI string(s) found (use t() from lib/i18n.ts or add i18n-ignore):\n`,
  );
  for (const p of problems) console.error("  " + p);
  process.exit(1);
}
console.log(`lint-strings: OK (${scanned} files scanned, allowlisted: ${ALLOW_PATHS.join(", ")})`);
