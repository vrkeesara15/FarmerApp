import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * A tiny in-memory router standing in for next/navigation: push adds a history entry,
 * replace overwrites it, back() steps back — enough to prove the AN-011 acceptance
 * "filters persist in the URL" (reload = re-parse the URL, back/forward = history).
 */
const nav = vi.hoisted(() => {
  const state = { history: ["/home"], index: 0, listeners: new Set<() => void>() };
  const url = () => new URL(state.history[state.index]!, "http://localhost");
  const emit = () => state.listeners.forEach((l) => l());
  return {
    state,
    url,
    reset(path: string) {
      state.history = [path];
      state.index = 0;
      emit();
    },
    push: vi.fn((to: string) => {
      state.history = state.history.slice(0, state.index + 1);
      state.history.push(to);
      state.index += 1;
      emit();
    }),
    replace: vi.fn((to: string) => {
      state.history[state.index] = to;
      emit();
    }),
    back() {
      state.index = Math.max(0, state.index - 1);
      emit();
    },
    forward() {
      state.index = Math.min(state.history.length - 1, state.index + 1);
      emit();
    },
  };
});

vi.mock("next/navigation", async () => {
  const React = await import("react");
  const useLocation = () =>
    React.useSyncExternalStore(
      (l: () => void) => {
        nav.state.listeners.add(l);
        return () => nav.state.listeners.delete(l);
      },
      () => nav.state.history[nav.state.index]!,
    );
  return {
    useRouter: () => ({ push: nav.push, replace: nav.replace }),
    usePathname: () => new URL(useLocation(), "http://localhost").pathname,
    useSearchParams: () => new URL(useLocation(), "http://localhost").searchParams,
  };
});

import { defaultRange, todayIst } from "../analytics-filters";
import { useAnalyticsFilters, useSearchParam } from "./use-analytics-filters";

beforeEach(() => {
  nav.push.mockClear();
  nav.replace.mockClear();
});

describe("useAnalyticsFilters", () => {
  it("starts from the defaults (last 30 days) when the URL has no filters", () => {
    nav.reset("/home");
    const { result } = renderHook(() => useAnalyticsFilters());
    expect(result.current.filters).toEqual(defaultRange(todayIst()));
    expect(result.current.isDefaultRange).toBe(true);
    expect(result.current.activeCount).toBe(0);
    expect(result.current.linkQuery).toBe("");
    expect(result.current.apiFilters).toEqual(defaultRange(todayIst()));
  });

  it("writes a change to the URL (push), keeps other parameters, and re-reads it", () => {
    nav.reset("/farmers?q=ram&sort=-ltv");
    const { result } = renderHook(() => useAnalyticsFilters());
    act(() =>
      result.current.setFilters({ store: "store-wgl", from: "2026-07-01", to: "2026-07-31" }),
    );
    expect(nav.push).toHaveBeenCalledTimes(1);
    expect(nav.url().pathname).toBe("/farmers");
    expect(nav.url().search).toBe("?from=2026-07-01&to=2026-07-31&store=store-wgl&q=ram&sort=-ltv");
    expect(result.current.filters).toEqual({
      from: "2026-07-01",
      to: "2026-07-31",
      store: "store-wgl",
    });
    expect(result.current.apiFilters).toEqual({
      from: "2026-07-01",
      to: "2026-07-31",
      store_id: "store-wgl",
    });
    expect(result.current.linkQuery).toBe("?from=2026-07-01&to=2026-07-31&store=store-wgl");
    expect(result.current.activeCount).toBe(2);
  });

  it("survives a reload: a fresh hook on the same URL reads the same filters", () => {
    nav.reset("/home?from=2026-06-01&to=2026-06-30&crop=crop-paddy&officer=off-wgl-1");
    const first = renderHook(() => useAnalyticsFilters()).result.current.filters;
    const reloaded = renderHook(() => useAnalyticsFilters()).result.current.filters;
    expect(reloaded).toEqual(first);
    expect(reloaded).toEqual({
      from: "2026-06-01",
      to: "2026-06-30",
      crop: "crop-paddy",
      officer: "off-wgl-1",
    });
  });

  it("back and forward step through filter changes", () => {
    nav.reset("/stores");
    const { result } = renderHook(() => useAnalyticsFilters());
    act(() => result.current.setFilters({ cluster: "cluster-tg" }));
    act(() => result.current.setFilters({ store: "store-wgl" }));
    expect(result.current.filters.store).toBe("store-wgl");
    act(() => nav.back());
    expect(result.current.filters).toMatchObject({ cluster: "cluster-tg" });
    expect(result.current.filters.store).toBeUndefined();
    act(() => nav.forward());
    expect(result.current.filters).toMatchObject({ cluster: "cluster-tg", store: "store-wgl" });
  });

  it("replace option corrects the URL without a history entry; reset keeps other params", () => {
    nav.reset("/home?from=2026-09-10&to=2026-09-01&q=x");
    const { result } = renderHook(() => useAnalyticsFilters());
    expect(result.current.issues).toEqual(["reversed_range"]);
    act(() => result.current.setFilters({}, { replace: true }));
    expect(nav.replace).toHaveBeenCalledTimes(1);
    expect(nav.state.history).toHaveLength(1);
    expect(nav.url().search).toBe("?from=2026-09-01&to=2026-09-10&q=x");
    expect(result.current.issues).toEqual([]);
    act(() => result.current.reset());
    expect(nav.url().search).toBe("?q=x");
    expect(result.current.isDefaultRange).toBe(true);
  });

  it("choosing a cluster clears a store and officer from another cluster", () => {
    nav.reset("/home?cluster=cluster-tg&store=store-wgl&officer=off-wgl-1");
    const { result } = renderHook(() => useAnalyticsFilters());
    act(() => result.current.setFilters({ cluster: "cluster-ka" }));
    expect(nav.url().search).toBe("?cluster=cluster-ka");
  });
});

describe("useSearchParam", () => {
  it("reads and writes one screen parameter next to the filters", () => {
    nav.reset("/field-team/off-1/replay?store=store-wgl");
    const { result } = renderHook(() => useSearchParam("date"));
    expect(result.current[0]).toBeUndefined();
    act(() => result.current[1]("2026-09-10"));
    expect(nav.url().search).toBe("?store=store-wgl&date=2026-09-10");
    expect(result.current[0]).toBe("2026-09-10");
    act(() => result.current[1](undefined, { replace: true }));
    expect(nav.url().search).toBe("?store=store-wgl");
  });
});
