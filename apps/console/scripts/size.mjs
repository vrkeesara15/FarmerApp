#!/usr/bin/env node
/**
 * size: prints the size of the production bundle in .next/static (JS + CSS), the ten largest
 * chunks, and fails when SIZE_LIMIT_KB is set and exceeded. Run after `npm run build`.
 */
import { readdirSync, statSync, existsSync } from "node:fs";
import { join, relative, resolve, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const staticDir = join(root, ".next", "static");
if (!existsSync(staticDir)) {
  console.error("size: .next/static not found — run `npm run build` first.");
  process.exit(1);
}

const files = [];
(function walk(dir) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) walk(full);
    else if ([".js", ".css"].includes(extname(entry)))
      files.push({ path: relative(staticDir, full), bytes: st.size });
  }
})(staticDir);

const kb = (b) => (b / 1024).toFixed(1).padStart(8) + " KB";
const total = files.reduce((a, f) => a + f.bytes, 0);
const js = files.filter((f) => f.path.endsWith(".js")).reduce((a, f) => a + f.bytes, 0);
const css = total - js;

files.sort((a, b) => b.bytes - a.bytes);
console.log("Largest chunks (.next/static):");
for (const f of files.slice(0, 10)) console.log(`${kb(f.bytes)}  ${f.path}`);
console.log(
  `\nTotal JS : ${kb(js)}\nTotal CSS: ${kb(css)}\nTotal    : ${kb(total)}  (${files.length} files, uncompressed)`,
);

const limit = Number(process.env.SIZE_LIMIT_KB || 0);
if (limit > 0 && total / 1024 > limit) {
  console.error(
    `\nsize: FAIL — total ${(total / 1024).toFixed(1)} KB exceeds SIZE_LIMIT_KB=${limit}`,
  );
  process.exit(1);
}
