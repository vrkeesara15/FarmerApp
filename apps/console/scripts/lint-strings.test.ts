import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

/** FA-004 acceptance: the string lint catches hard-coded JSX copy (spawned on fixtures). */
const script = resolve(__dirname, "lint-strings.mjs");

type Run = { code: number; out: string };
function run(...paths: string[]): Run {
  try {
    const out = execFileSync(process.execPath, [script, ...paths], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { code: 0, out };
  } catch (err) {
    const e = err as { status: number; stdout: string; stderr: string };
    return { code: e.status, out: `${e.stdout ?? ""}${e.stderr ?? ""}` };
  }
}

describe("scripts/lint-strings.mjs", () => {
  let dir: string;
  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), "lint-strings-"));
  });
  afterAll(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("fails on a raw JSX string and names the file, line and text", () => {
    const file = join(dir, "Bad.tsx");
    writeFileSync(
      file,
      'export function Bad() {\n  return <p className="x">Hello farmer</p>;\n}\n',
    );
    const r = run(file);
    expect(r.code).toBe(1);
    expect(r.out).toContain("raw JSX text");
    expect(r.out).toContain('"Hello farmer"');
    expect(r.out).toMatch(/Bad\.tsx:2:\d+/);
  });

  it("fails on raw user-facing attributes", () => {
    const file = join(dir, "Attr.tsx");
    writeFileSync(
      file,
      'export function Attr() {\n  return <input placeholder="Search" aria-label={"Find"} />;\n}\n',
    );
    const r = run(file);
    expect(r.code).toBe(1);
    expect(r.out).toContain("raw placeholder");
    expect(r.out).toContain("raw aria-label");
  });

  it("passes t() calls, numbers, punctuation and i18n-ignore", () => {
    const file = join(dir, "Good.tsx");
    writeFileSync(
      file,
      [
        'import { useT } from "@/lib/i18n";',
        "export function Good() {",
        "  const t = useT();",
        "  return (",
        "    <div>",
        '      <p>{t("home.title")}</p>',
        "      <span>+91</span>",
        "      <span>—</span>",
        "      {/* i18n-ignore */}",
        "      <span>తెలుగు</span>",
        '      <img alt="" />',
        "    </div>",
        "  );",
        "}",
        "",
      ].join("\n"),
    );
    const r = run(file);
    expect(r.code).toBe(0);
    expect(r.out).toContain("lint-strings: OK (1 files scanned");
  });

  it("scans a directory recursively", () => {
    const sub = join(dir, "tree", "deep");
    execFileSync("mkdir", ["-p", sub]);
    writeFileSync(join(sub, "Nested.tsx"), "export const N = () => <b>Nested copy</b>;\n");
    const r = run(join(dir, "tree"));
    expect(r.code).toBe(1);
    expect(r.out).toContain("Nested.tsx");
  });
});
