import { createHash } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { handleDiagnosis, handleUploads, resetMockDiagnosis } from "./diagnosis";

const AGRO = { id: "u-agronomist", role: "agronomist" };
const OWNER = { id: "u-owner", role: "owner" };
const q = (s = "") => new URLSearchParams(s);
type J = Record<string, unknown> & { items?: Array<Record<string, unknown>> };
const call = (
  method: string,
  path: string,
  body: Record<string, unknown> = {},
  actor = AGRO,
  query = "",
) => {
  const res = handleDiagnosis(method, path.split("/"), q(query), body, actor)!;
  return { status: res.status, json: res.json as J };
};

describe("mock crop doctor API (mirrors apps/api for C60-C62)", () => {
  beforeEach(() => resetMockDiagnosis());

  it("serves the review queue oldest first with SLA flags to agronomists and owners only", () => {
    const { status, json } = call("GET", "diagnoses/review-queue");
    expect(status).toBe(200);
    const items = json.items!;
    const created = items.map((i) => String(i.created_at));
    expect(created).toEqual([...created].sort());
    expect(items[0]).toMatchObject({ overdue: true, status: "provisional" });
    expect(json.counts).toMatchObject({ total: items.length, overdue: 2 });
    expect(call("GET", "diagnoses/review-queue", {}, OWNER).status).toBe(200);
    expect(call("GET", "diagnoses/review-queue", {}, { id: "x", role: "director" }).status).toBe(
      403,
    );
    expect(call("GET", "diagnoses/review-queue", {}, AGRO, "flagged=true").json.items).toHaveLength(
      1,
    );
  });

  it("a correction rebuilds the farmer result, adds reviewed corpus images and leaves the queue", () => {
    const item = call("GET", "diagnoses/review-queue").json.items![1]!;
    const zinc = (item.scores as { candidates: Array<{ problem_id: string }> }).candidates[1]!
      .problem_id;
    expect(
      call("POST", `diagnoses/${item.id}/review`, { action: "correct", note: "" }).status,
    ).toBe(422);
    expect(
      call("POST", `diagnoses/${item.id}/review`, {
        action: "correct",
        problem_id: "nope",
        note: "x",
      }).json.code,
    ).toBe("review_invalid");
    expect(
      call("POST", `diagnoses/${item.id}/review`, { action: "confirm", note: "x" }, OWNER).status,
    ).toBe(403);
    const { status, json } = call("POST", `diagnoses/${item.id}/review`, {
      action: "correct",
      problem_id: zinc,
      note: "Rusty spots",
      add_to_corpus: true,
    });
    expect(status).toBe(200);
    expect(json).toMatchObject({
      status: "corrected",
      source: "agronomist",
      can_buy: true,
      final_problem_id: zinc,
    });
    const review = (json.reviews as Array<{ corpus_image_ids: string[] }>)[0]!;
    expect(review.corpus_image_ids.length).toBeGreaterThan(0);
    const ids = call("GET", "diagnoses/review-queue").json.items!.map((i) => i.id);
    expect(ids).not.toContain(item.id);
    const images = call("GET", `corpus/problems/${zinc}/images`, {}, AGRO, "status=reviewed").json
      .items!;
    expect(images.some((i) => i.from_diagnosis_id === item.id)).toBe(true);
  });

  it("corpus workflow: draft -> reviewed -> approved bumps the version once; locked after approval", () => {
    const before = call("GET", "corpus/versions").json.current as number;
    const created = call("POST", "corpus/problems", {
      pest_or_disease_id: "pest-paddy_bph",
      crop_id: "crop-paddy",
      names: { en: "Brown planthopper" },
      symptoms: { en: ["Hopper burn"] },
    });
    expect(created.status).toBe(201);
    expect(created.json).toMatchObject({ status: "draft", problem_type: "pest" });
    const id = String(created.json.id);
    expect(
      call("POST", "corpus/problems", {
        pest_or_disease_id: "pest-paddy_bph",
        crop_id: "crop-paddy",
        names: { en: "x" },
      }).json.code,
    ).toBe("corpus_problem_exists");
    expect(call("POST", `corpus/problems/${id}/transition`, { to: "approved" }).json.code).toBe(
      "invalid_transition",
    );
    expect(call("POST", `corpus/problems/${id}/transition`, { to: "reviewed" }).json.status).toBe(
      "reviewed",
    );
    expect(call("GET", "corpus/versions").json.current).toBe(before);
    const approved = call("POST", `corpus/problems/${id}/transition`, { to: "approved" });
    expect(approved.json).toMatchObject({ status: "approved", approved_in_version: before + 1 });
    expect(call("GET", "corpus/versions").json.current).toBe(before + 1);
    expect(call("PATCH", `corpus/problems/${id}`, { notes: "x" }).json.code).toBe(
      "corpus_entry_locked",
    );
    expect(call("POST", `corpus/problems/${id}/transition`, { to: "reviewed" }, OWNER).status).toBe(
      403,
    );
    const served = call("GET", "corpus/problems", {}, OWNER, "status=approved").json.items!;
    expect(served.every((p) => p.status === "approved")).toBe(true);
  });

  it("approvals approve a problem and its images in one version", () => {
    const draft = call("GET", "corpus/problems", {}, AGRO, "status=reviewed").json.items![0]!;
    const images = call("GET", `corpus/problems/${draft.id}/images`).json.items!;
    for (const i of images) call("POST", `corpus/images/${i.id}/transition`, { to: "reviewed" });
    const before = call("GET", "corpus/versions").json.current as number;
    const v = call("POST", "corpus/approvals", {
      problem_ids: [draft.id],
      image_ids: images.map((i) => i.id),
      note: "Field set",
    });
    expect(v.status).toBe(201);
    expect(v.json.version).toBe(before + 1);
    expect(call("GET", `corpus/problems/${draft.id}`).json.image_counts).toEqual({
      approved: images.length,
    });
  });

  it("chunked upload then attach embeds the image as a draft", async () => {
    const bytes = new TextEncoder().encode("fake-jpeg-bytes");
    const sha = createHash("sha256").update(bytes).digest("hex");
    const enc = (o: unknown) => new TextEncoder().encode(JSON.stringify(o)).buffer as ArrayBuffer;
    const init = await handleUploads(
      "POST",
      ["uploads"],
      enc({ sha256: sha, size_bytes: bytes.length, content_type: "image/jpeg", purpose: "corpus" }),
      new Headers(),
      AGRO,
    );
    expect(init!.status).toBe(201);
    const id = (init!.json as { upload_id: string }).upload_id;
    const missing = await handleUploads(
      "PUT",
      ["uploads", id, "chunks", "0"],
      bytes.buffer as ArrayBuffer,
      new Headers(),
      AGRO,
    );
    expect((missing!.json as { code: string }).code).toBe("chunk_sha_missing");
    const put = await handleUploads(
      "PUT",
      ["uploads", id, "chunks", "0"],
      bytes.buffer as ArrayBuffer,
      new Headers({ "x-chunk-sha256": sha }),
      AGRO,
    );
    expect(put!.status).toBe(200);
    const done = await handleUploads(
      "POST",
      ["uploads", id, "complete"],
      new ArrayBuffer(0),
      new Headers(),
      AGRO,
    );
    const blob = done!.json as { blob_uri: string; sha256: string };
    expect(blob.sha256).toBe(sha);
    const problem = call("GET", "corpus/problems", {}, AGRO, "status=draft").json.items![0]!;
    const img = call("POST", `corpus/problems/${problem.id}/images`, {
      blob_uri: blob.blob_uri,
      sha256: sha,
      part: "leaf",
    });
    expect(img.status).toBe(201);
    expect(img.json).toMatchObject({
      status: "draft",
      encoder_name: "siglip-base-patch16-224",
      part: "leaf",
    });
    expect(String(img.json.signed_url)).toMatch(/^data:image\/jpeg;base64,/);
    expect(
      call("POST", `corpus/problems/${problem.id}/images`, { blob_uri: blob.blob_uri }).json.code,
    ).toBe("corpus_image_exists");
  });
});
