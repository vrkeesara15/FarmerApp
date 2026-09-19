/**
 * Resumable chunked upload (NF-003, apps/api/openapi.yaml `initUpload` / `putUploadChunk` /
 * `completeUpload`): POST /v1/uploads with the whole-file sha256, PUT each 256 KB chunk with its
 * own `X-Chunk-Sha256`, then POST /complete -> `blob_uri`. The corpus manager (WC-007) attaches
 * the blob to a problem afterwards.
 */
import { API_BASE_URL, ApiError, authedFetch, getAuthToken, session } from "./api";

export const CHUNK_SIZE = 262_144;
export type UploadPurpose = "corpus" | "diagnosis";

export interface UploadStatus {
  upload_id: string;
  status: "pending" | "complete";
  chunk_size: number;
  chunk_count: number;
  size_bytes: number;
  received_chunks: number[];
  expires_at: string;
  blob_uri?: string | null;
}

export interface UploadComplete {
  upload_id: string;
  blob_uri: string;
  sha256: string;
  size_bytes: number;
  content_type: string;
}

const HEX = (buf: ArrayBuffer) =>
  [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

export async function sha256Hex(data: ArrayBuffer): Promise<string> {
  return HEX(await crypto.subtle.digest("SHA-256", data));
}

/** Byte ranges of the chunks of a file of `size` bytes. */
export function chunkRanges(size: number, chunkSize = CHUNK_SIZE): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  for (let start = 0; start < size; start += chunkSize)
    out.push([start, Math.min(size, start + chunkSize)]);
  return out;
}

async function putChunk(uploadId: string, index: number, bytes: ArrayBuffer): Promise<void> {
  const send = async () => {
    const token = getAuthToken();
    return fetch(`${API_BASE_URL}/v1/uploads/${uploadId}/chunks/${index}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-Chunk-Sha256": await sha256Hex(bytes),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: bytes,
    });
  };
  let res = await send();
  if (res.status === 401 && (await session.refresh())) res = await send();
  if (!res.ok) {
    let problem: Record<string, unknown> = {};
    try {
      problem = (await res.json()) as Record<string, unknown>;
    } catch {
      /* not json */
    }
    throw new ApiError({
      ...problem,
      title: String(problem.title ?? res.statusText ?? "Upload failed"),
      status: res.status,
    });
  }
}

/** Uploads `file`, reporting progress (0..1) after each chunk; resolves with the blob. */
export async function uploadFile(
  file: Blob & { type: string },
  purpose: UploadPurpose,
  onProgress?: (fraction: number) => void,
): Promise<UploadComplete> {
  const bytes = await file.arrayBuffer();
  const sha256 = await sha256Hex(bytes);
  const init = await authedFetch<UploadStatus>("v1/uploads", {
    body: {
      sha256,
      size_bytes: bytes.byteLength,
      content_type: file.type || "image/jpeg",
      purpose,
      chunk_size: CHUNK_SIZE,
    },
  });
  const ranges = chunkRanges(bytes.byteLength, init.chunk_size || CHUNK_SIZE);
  const have = new Set(init.received_chunks ?? []);
  for (const [i, [start, end]] of ranges.entries()) {
    if (!have.has(i)) await putChunk(init.upload_id, i, bytes.slice(start, end));
    onProgress?.((i + 1) / ranges.length);
  }
  return authedFetch<UploadComplete>(`v1/uploads/${init.upload_id}/complete`, { method: "POST" });
}
