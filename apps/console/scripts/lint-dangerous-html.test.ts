import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

/** SEC-022 acceptance: the output-encoding lint catches new unsafe HTML sinks. */
const script = resolve(__dirname, "lint-dangerous-html.mjs");

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

describe("scripts/lint-dangerous-html.mjs", () => {
  let dir: string;
  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), "lint-dangerous-"));
  });
  afterAll(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("fails on a new dangerouslySetInnerHTML and names the file and line", () => {
    const file = join(dir, "Bad.tsx");
    const sink = ["dangerously", "SetInnerHTML"].join("");
    writeFileSync(
      file,
      `export function Bad({ html }: { html: string }) {\n  return <div ${sink}={{ __html: html }} />;\n}\n`,
    );
    const r = run(file);
    expect(r.code).toBe(1);
    expect(r.out).toContain(sink);
    expect(r.out).toMatch(/Bad\.tsx:2/);
  });

  it("fails on raw innerHTML and document.write", () => {
    const file = join(dir, "Sinks.ts");
    writeFileSync(
      file,
      "export function boom(el: HTMLElement, s: string) {\n" +
        "  el.innerHTML = s;\n" +
        "  document.write(s);\n" +
        "}\n",
    );
    const r = run(file);
    expect(r.code).toBe(1);
    expect(r.out).toContain("innerHTML assignment");
    expect(r.out).toContain("document.write");
  });

  it("passes ordinary React output", () => {
    const file = join(dir, "Good.tsx");
    writeFileSync(file, "export const Good = ({ s }: { s: string }) => <p>{s}</p>;\n");
    const r = run(file);
    expect(r.code).toBe(0);
    expect(r.out).toContain("lint-dangerous-html: OK (1 files scanned");
  });

  it("passes the real tree: the only sinks are the two allowlisted layout scripts", () => {
    const r = run();
    expect(r.out).toContain("app/layout.tsx");
    expect(r.code).toBe(0);
  });
});
