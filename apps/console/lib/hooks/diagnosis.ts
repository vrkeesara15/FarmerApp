"use client";

/**
 * TanStack Query hooks over lib/diagnosis.ts and lib/corpus.ts (WC-006, WC-007). Queries wait
 * for the session; mutations refresh the queue / corpus lists they change.
 */
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  corpusApi,
  type CorpusImageInput,
  type CorpusProblemFilters,
  type CorpusProblemInput,
  type CorpusProblemPatch,
  type CorpusStatus,
} from "../corpus";
import { diagnosisApi, type ReviewInput, type ReviewQueueFilters } from "../diagnosis";
import { useSession } from "../session-context";
import { uploadFile } from "../uploads";

export const diagnosisKeys = {
  queue: (f: ReviewQueueFilters) => ["diagnoses", "queue", f] as const,
  detail: (id: string) => ["diagnoses", "detail", id] as const,
  recent: () => ["diagnoses", "recent"] as const,
};

export const corpusKeys = {
  all: ["corpus"] as const,
  problems: (f: CorpusProblemFilters) => ["corpus", "problems", f] as const,
  problem: (id: string) => ["corpus", "problem", id] as const,
  images: (id: string) => ["corpus", "images", id] as const,
  versions: () => ["corpus", "versions"] as const,
};

function useReady(): boolean {
  return useSession().status === "authenticated";
}

// ---- review queue (C60) ------------------------------------------------------------------
export function useReviewQueue(filters: ReviewQueueFilters, enabled = true) {
  const ready = useReady();
  return useInfiniteQuery({
    queryKey: diagnosisKeys.queue(filters),
    queryFn: ({ pageParam }) => diagnosisApi.queue({ ...filters, cursor: pageParam }),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    enabled: ready && enabled,
  });
}

export function useReviewDiagnosis(id: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: ReviewInput) => diagnosisApi.review(id, body),
    onSuccess: (detail) => {
      qc.setQueryData(diagnosisKeys.detail(id), detail);
      void qc.invalidateQueries({ queryKey: ["diagnoses"] });
      void qc.invalidateQueries({ queryKey: corpusKeys.all });
    },
  });
}

/**
 * Recent diagnoses for C62: newest first, up to `pages` x 200 rows, cut at `sinceDays`
 * (the list has no date filter; AN-007 in M7 replaces this with a server summary).
 */
export function useRecentDiagnoses(sinceDays = 30, pages = 5) {
  const ready = useReady();
  return useQuery({
    queryKey: [...diagnosisKeys.recent(), sinceDays] as const,
    enabled: ready,
    queryFn: async () => {
      const since = Date.now() - sinceDays * 86_400_000;
      const items = [];
      let cursor: string | null | undefined = null;
      for (let i = 0; i < pages; i++) {
        const page = await diagnosisApi.list({ cursor, limit: 200 });
        const inRange = page.items.filter((d) => new Date(d.created_at).getTime() >= since);
        items.push(...inRange);
        cursor = page.next_cursor;
        if (!cursor || inRange.length < page.items.length) break;
      }
      return items;
    },
  });
}

// ---- corpus (C61) ------------------------------------------------------------------------
export function useCorpusProblems(filters: CorpusProblemFilters = {}, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: corpusKeys.problems(filters),
    queryFn: () => corpusApi.problems(filters),
    enabled: ready && enabled,
  });
}

export function useCorpusImages(problemId: string | null) {
  const ready = useReady();
  return useQuery({
    queryKey: corpusKeys.images(problemId ?? ""),
    queryFn: () => corpusApi.images(problemId!),
    enabled: ready && !!problemId,
  });
}

export function useCorpusVersions() {
  const ready = useReady();
  return useQuery({
    queryKey: corpusKeys.versions(),
    queryFn: corpusApi.versions,
    enabled: ready,
  });
}

function useCorpusMutation<V, R>(fn: (vars: V) => Promise<R>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: corpusKeys.all }),
  });
}

export const useCreateProblem = () =>
  useCorpusMutation((body: CorpusProblemInput) => corpusApi.createProblem(body));
export const useUpdateProblem = () =>
  useCorpusMutation(({ id, body }: { id: string; body: CorpusProblemPatch }) =>
    corpusApi.updateProblem(id, body),
  );
export const useTransitionProblem = () =>
  useCorpusMutation(({ id, to, note }: { id: string; to: CorpusStatus; note: string | null }) =>
    corpusApi.transitionProblem(id, to, note),
  );
export const useTransitionImage = () =>
  useCorpusMutation(({ id, to, note }: { id: string; to: CorpusStatus; note: string | null }) =>
    corpusApi.transitionImage(id, to, note),
  );
export const useApproveCorpus = () =>
  useCorpusMutation((body: { problem_ids: string[]; image_ids: string[]; note: string | null }) =>
    corpusApi.approve(body),
  );

/** Chunked upload (purpose `corpus`) then attach to the problem; the server embeds it. */
export function useUploadCorpusImage(problemId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({
      file,
      meta,
      onProgress,
    }: {
      file: File;
      meta: Omit<CorpusImageInput, "blob_uri" | "sha256">;
      onProgress?: (phase: "uploading" | "embedding", fraction: number) => void;
    }) => {
      const blob = await uploadFile(file, "corpus", (f) => onProgress?.("uploading", f));
      onProgress?.("embedding", 1);
      return corpusApi.addImage(problemId, {
        ...meta,
        blob_uri: blob.blob_uri,
        sha256: blob.sha256,
      });
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: corpusKeys.all }),
  });
}
