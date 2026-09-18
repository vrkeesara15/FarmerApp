"use client";

import { Toaster } from "@/components/ui/sonner";
import { toast as sonnerToast } from "sonner";
import { ApiError } from "@/lib/api";
import { t } from "@/lib/i18n";

/** Mount once in the root layout. */
export function Toasts() {
  return <Toaster position="bottom-right" closeButton richColors={false} />;
}

export const toast = {
  success: (message: string, description?: string) => sonnerToast.success(message, { description }),
  error: (message: string, description?: string) => sonnerToast.error(message, { description }),
  info: (message: string, description?: string) => sonnerToast(message, { description }),
  warning: (message: string, description?: string) => sonnerToast.warning(message, { description }),
  /** Surface an ApiError (problem+json) or unknown error with a friendly title. */
  fromError: (err: unknown) => {
    if (err instanceof ApiError)
      return sonnerToast.error(err.problem.title, { description: err.problem.detail });
    return sonnerToast.error(t("toast.error"), {
      description: err instanceof Error ? err.message : undefined,
    });
  },
  dismiss: sonnerToast.dismiss,
};
