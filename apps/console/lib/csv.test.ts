import { afterEach, describe, expect, it, vi } from "vitest";
import { CSV_BOM, csvCell, csvFilename, downloadCsv, paiseToRupees, toCsv } from "./csv";

describe("CSV export of a table view", () => {
  afterEach(() => vi.restoreAllMocks());

  it("quotes commas, quotes and newlines (RFC 4180) with CRLF rows", () => {
    const csv = toCsv(
      [
        { header: "Name", value: (r: { n: string; v: number }) => r.n },
        { header: "Value", value: (r: { n: string; v: number }) => r.v },
      ],
      [
        { n: 'Ramesh "Ram" Reddy', v: 1 },
        { n: "Warangal, TG", v: 2.5 },
        { n: "two\nlines", v: -3 },
      ],
    );
    expect(csv).toBe(
      'Name,Value\r\n"Ramesh ""Ram"" Reddy",1\r\n"Warangal, TG",2.5\r\n"two\nlines",-3\r\n',
    );
  });

  it("neutralises formula-looking text but not negative numbers", () => {
    expect(csvCell("=HYPERLINK(1)")).toBe("'=HYPERLINK(1)");
    expect(csvCell("+91 98480")).toBe("'+91 98480");
    expect(csvCell("@cmd")).toBe("'@cmd");
    expect(csvCell(-500)).toBe("-500");
    expect(csvCell(null)).toBe("");
    expect(csvCell(Number.NaN)).toBe("");
    expect(csvCell(true)).toBe("true");
  });

  it("keeps Indic text and money as rupees", () => {
    expect(csvCell("రమేష్")).toBe("రమేష్");
    expect(paiseToRupees(1_25_000_50)).toBe(125000.5);
    expect(paiseToRupees(null)).toBeNull();
    expect(csvFilename("farmers", "2026-08-01", "2026-08-30")).toBe(
      "farmers_2026-08-01_2026-08-30.csv",
    );
    expect(csvFilename("pnl")).toBe("pnl.csv");
  });

  it("downloads with a UTF-8 BOM", async () => {
    const blobs: Blob[] = [];
    Object.assign(URL, {
      createObjectURL: vi.fn((b: Blob) => {
        blobs.push(b);
        return "blob:x";
      }),
      revokeObjectURL: vi.fn(),
    });
    const click = vi
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => undefined);
    downloadCsv("x.csv", [{ header: "A", value: (r: { a: string }) => r.a }], [{ a: "1" }]);
    expect(click).toHaveBeenCalled();
    const bytes = await new Promise<Uint8Array>((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(new Uint8Array(reader.result as ArrayBuffer));
      reader.readAsArrayBuffer(blobs[0]!);
    });
    expect([...bytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    expect(new TextDecoder("utf-8", { ignoreBOM: true }).decode(bytes)).toBe(
      `${CSV_BOM}A\r\n1\r\n`,
    );
    expect(blobs[0]!.type).toBe("text/csv;charset=utf-8");
  });
});
