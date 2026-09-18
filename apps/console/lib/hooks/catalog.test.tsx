import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { installCatalogFetch } from "@/test/mock-fetch";
import { setAuthToken, setCurrentUser, type AuthUser } from "../api";
import { SessionProvider } from "../session-context";
import {
  useApproveClaim,
  useCreateClaim,
  useLabelClaims,
  useProducts,
  usePutPriceLists,
  useRecommendable,
  useRetireClaim,
} from "./catalog";

const user = (role: string): AuthUser => ({
  id: `u-${role}`,
  tenant_id: "t1",
  phone: "+919000000000",
  name: "Test",
  role,
  store_id: null,
  cluster_id: null,
  language: "en",
  status: "active",
});

function signIn(role: string) {
  setAuthToken(`mock-access-${role}-1`);
  setCurrentUser(user(role));
}

function wrapper() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <QueryClientProvider client={client}>
        <SessionProvider>{children}</SessionProvider>
      </QueryClientProvider>
    );
  }
  return Wrapper;
}

afterEach(() => {
  vi.restoreAllMocks();
  setAuthToken(null);
});

describe("catalogue hooks (TanStack Query over lib/catalog.ts)", () => {
  it("send the bearer token and return products with SKUs", async () => {
    const { calls } = installCatalogFetch();
    signIn("owner");
    const { result } = renderHook(() => useProducts({ own_brand: true }), { wrapper: wrapper() });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.map((p) => p.name)).toEqual(["FCC Imida"]);
    expect(result.current.data?.[0]?.skus).toHaveLength(2);
    const call = calls.find((c) => c.path.startsWith("/api/mock/v1/catalog/products"));
    expect(call?.authorization).toBe("Bearer mock-access-owner-1");
    expect(call?.path).toContain("own_brand=true");
  });

  it("restore the session from the refresh cookie before querying", async () => {
    const { calls } = installCatalogFetch({ refreshRole: "agronomist" });
    const { result } = renderHook(() => useLabelClaims({ status: "all" }), { wrapper: wrapper() });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(calls[0]?.path).toBe("/api/session/refresh");
    expect(result.current.data?.map((c) => c.status).sort()).toEqual([
      "approved",
      "draft",
      "retired",
    ]);
  });

  it("stay idle when signed out", async () => {
    const { calls } = installCatalogFetch({ refreshRole: null });
    const { result } = renderHook(() => useProducts(), { wrapper: wrapper() });
    await waitFor(() => expect(calls).toHaveLength(1));
    expect(result.current.fetchStatus).toBe("idle");
    expect(calls.every((c) => c.path === "/api/session/refresh")).toBe(true);
  });

  it("approve / retire invalidate the recommendation preview (guardrail)", async () => {
    installCatalogFetch();
    signIn("agronomist");
    const { result } = renderHook(
      () => ({
        rec: useRecommendable("crop-paddy", "pest-paddy_bph"),
        create: useCreateClaim(),
        approve: useApproveClaim(),
        retire: useRetireClaim(),
      }),
      { wrapper: wrapper() },
    );
    await waitFor(() =>
      expect(result.current.rec.data?.map((r) => r.sku_id)).toEqual(["sku-imida-100"]),
    );
    let id = "";
    await act(async () => {
      const draft = await result.current.create.mutateAsync({
        sku_id: "sku-imida-250",
        crop_id: "crop-paddy",
        pest_or_disease_id: "pest-paddy_bph",
        dose_per_acre: "100 ml",
        dose_value: "100",
        dose_unit: "ml",
        dose_per_tank_15l: null,
        phi_days: 30,
        ppe_text: null,
        safety_text: null,
        source_ref: "CIB-1",
        efficacy_tier: null,
      });
      id = draft.id;
    });
    expect(result.current.rec.data).toHaveLength(1);
    await act(async () => {
      await result.current.approve.mutateAsync(id);
    });
    await waitFor(() => expect(result.current.rec.data).toHaveLength(2));
    await act(async () => {
      await result.current.retire.mutateAsync(id);
    });
    await waitFor(() =>
      expect(result.current.rec.data?.map((r) => r.sku_id)).toEqual(["sku-imida-100"]),
    );
  });

  it("surface per-row price problems from the API", async () => {
    installCatalogFetch();
    signIn("owner");
    const { result } = renderHook(() => usePutPriceLists(), { wrapper: wrapper() });
    await act(async () => {
      await expect(
        result.current.mutateAsync({
          storeId: null,
          items: [
            {
              sku_id: "sku-imida-100",
              price_paise: 999_999,
              effective_from: "2027-01-01",
              effective_to: null,
            },
          ],
        }),
      ).rejects.toMatchObject({
        status: 422,
        problem: { code: "price_above_mrp", rows: [{ index: 0 }] },
      });
    });
  });
});
