"use client";

import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toasts } from "@/components/ds/Toasts";
import { ApiError } from "@/lib/api";
import { initLocaleFromStorage } from "@/lib/i18n";

function makeQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        refetchOnWindowFocus: false,
        retry: (failureCount, error) => {
          // Never retry client errors (4xx); retry network/5xx up to twice.
          if (error instanceof ApiError && error.status >= 400 && error.status < 500) return false;
          return failureCount < 2;
        },
      },
      mutations: { retry: false },
    },
  });
}

/** Applies the persisted language after hydration (FA-004); `<html lang>` + subscribers. */
function LocaleBoot() {
  React.useEffect(() => {
    initLocaleFromStorage();
  }, []);
  return null;
}

/** Client layout wrapper: TanStack Query + toasts + locale boot. Used by the root layout. */
export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = React.useState(makeQueryClient);
  return (
    <QueryClientProvider client={queryClient}>
      <LocaleBoot />
      {children}
      <Toasts />
    </QueryClientProvider>
  );
}
