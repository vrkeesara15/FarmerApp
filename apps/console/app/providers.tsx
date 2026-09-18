"use client";

import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toasts } from "@/components/ds/Toasts";
import { ApiError } from "@/lib/api";

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

/** Client layout wrapper: TanStack Query + toasts. Used by the root layout. */
export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = React.useState(makeQueryClient);
  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <Toasts />
    </QueryClientProvider>
  );
}
