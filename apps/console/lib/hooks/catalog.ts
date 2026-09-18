"use client";

/** TanStack Query hooks over lib/catalog.ts (WC-005). Queries wait for the session. */
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  catalog,
  type ClaimFilters,
  type ImportKind,
  type LabelClaimInput,
  type LabelClaimPatch,
  type PriceRowInput,
  type ProductFilters,
  type ProductInput,
  type SkuInput,
} from "../catalog";
import { useSession } from "../session-context";

export const catalogKeys = {
  all: ["catalog"] as const,
  crops: () => ["catalog", "crops"] as const,
  pests: (cropId?: string) => ["catalog", "pests", cropId ?? null] as const,
  stores: () => ["catalog", "stores"] as const,
  products: (f: ProductFilters) => ["catalog", "products", f] as const,
  claims: (f: ClaimFilters) => ["catalog", "claims", f] as const,
  history: (id: string) => ["catalog", "claim-history", id] as const,
  recommendable: (cropId: string, pestId: string) =>
    ["catalog", "recommendable", cropId, pestId] as const,
  prices: (storeId: string | null) => ["catalog", "prices", storeId] as const,
};

function useReady(): boolean {
  return useSession().status === "authenticated";
}

export function useCrops() {
  const ready = useReady();
  return useQuery({
    queryKey: catalogKeys.crops(),
    queryFn: catalog.crops,
    enabled: ready,
    staleTime: 5 * 60_000,
  });
}

export function usePests(cropId?: string) {
  const ready = useReady();
  return useQuery({
    queryKey: catalogKeys.pests(cropId),
    queryFn: () => catalog.pests(cropId),
    enabled: ready,
    staleTime: 5 * 60_000,
  });
}

export function useStores(enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: catalogKeys.stores(),
    queryFn: catalog.stores,
    enabled: ready && enabled,
    staleTime: 5 * 60_000,
  });
}

export function useProducts(filters: ProductFilters = {}) {
  const ready = useReady();
  return useQuery({
    queryKey: catalogKeys.products(filters),
    queryFn: () => catalog.products(filters),
    enabled: ready,
  });
}

export function useLabelClaims(filters: ClaimFilters = {}) {
  const ready = useReady();
  return useQuery({
    queryKey: catalogKeys.claims(filters),
    queryFn: () => catalog.labelClaims(filters),
    enabled: ready,
  });
}

export function useClaimHistory(id: string | null) {
  const ready = useReady();
  return useQuery({
    queryKey: catalogKeys.history(id ?? ""),
    queryFn: () => catalog.claimHistory(id ?? ""),
    enabled: ready && !!id,
  });
}

export function useRecommendable(cropId: string | undefined, pestId: string | undefined) {
  const ready = useReady();
  return useQuery({
    queryKey: catalogKeys.recommendable(cropId ?? "", pestId ?? ""),
    queryFn: () => catalog.recommendable(cropId ?? "", pestId ?? ""),
    enabled: ready && !!cropId && !!pestId,
    staleTime: 0,
  });
}

export function usePriceLists(storeId: string | null, enabled = true) {
  const ready = useReady();
  return useQuery({
    queryKey: catalogKeys.prices(storeId),
    queryFn: () => catalog.priceLists(storeId),
    enabled: ready && enabled,
  });
}

/** Every catalogue write invalidates the whole catalogue cache (lists are small). */
function useCatalogMutation<V, R>(fn: (vars: V) => Promise<R>) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => qc.invalidateQueries({ queryKey: catalogKeys.all }),
  });
}

export const useCreateProduct = () =>
  useCatalogMutation((body: ProductInput) => catalog.createProduct(body));
export const useUpdateProduct = () =>
  useCatalogMutation(
    ({ id, body }: { id: string; body: Partial<ProductInput> & { version?: number } }) =>
      catalog.updateProduct(id, body),
  );
export const useCreateSku = () => useCatalogMutation((body: SkuInput) => catalog.createSku(body));
export const useUpdateSku = () =>
  useCatalogMutation(
    ({
      id,
      body,
    }: {
      id: string;
      body: Partial<Omit<SkuInput, "product_id">> & { version?: number };
    }) => catalog.updateSku(id, body),
  );
export const useCreateClaim = () =>
  useCatalogMutation((body: LabelClaimInput) => catalog.createClaim(body));
export const useUpdateClaim = () =>
  useCatalogMutation(({ id, body }: { id: string; body: LabelClaimPatch }) =>
    catalog.updateClaim(id, body),
  );
export const useApproveClaim = () => useCatalogMutation((id: string) => catalog.approveClaim(id));
export const useRetireClaim = () => useCatalogMutation((id: string) => catalog.retireClaim(id));
export const usePutPriceLists = () =>
  useCatalogMutation(({ storeId, items }: { storeId: string | null; items: PriceRowInput[] }) =>
    catalog.putPriceLists(storeId, items),
  );
export const useImportCsv = () =>
  useCatalogMutation(({ kind, csv, dryRun }: { kind: ImportKind; csv: string; dryRun: boolean }) =>
    catalog.importCsv(kind, csv, dryRun),
  );
