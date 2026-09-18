"use client";

import { Toaster as Sonner, type ToasterProps } from "sonner";

const Toaster = ({ ...props }: ToasterProps) => (
  <Sonner
    className="toaster group"
    toastOptions={{
      classNames: {
        toast:
          "group toast group-[.toaster]:bg-surface group-[.toaster]:text-text group-[.toaster]:border-border group-[.toaster]:shadow-sheet group-[.toaster]:rounded-card",
        description: "group-[.toast]:text-text-secondary",
        actionButton: "group-[.toast]:bg-primary group-[.toast]:text-primary-on",
        cancelButton: "group-[.toast]:bg-background group-[.toast]:text-text-secondary",
        success: "group-[.toaster]:border-success",
        error: "group-[.toaster]:border-danger",
        warning: "group-[.toaster]:border-warning",
        info: "group-[.toaster]:border-info",
      },
    }}
    {...props}
  />
);

export { Toaster };
export { toast } from "sonner";
