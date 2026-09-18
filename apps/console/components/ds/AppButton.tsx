"use client";

import * as React from "react";
import { Loader2 } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export type AppButtonVariant = "primary" | "secondary" | "tertiary" | "destructive";
export type AppButtonSize = "L" | "M";

export interface AppButtonProps extends Omit<ButtonProps, "variant" | "size"> {
  variant?: AppButtonVariant;
  size?: AppButtonSize;
  /** Optional leading icon (24px outlined, lucide). */
  icon?: React.ReactNode;
  /** Shows a spinner, sets aria-busy and disables the button. */
  loading?: boolean;
  /** Stretch to container width (primary actions). */
  fullWidth?: boolean;
}

const variantMap: Record<AppButtonVariant, ButtonProps["variant"]> = {
  primary: "default",
  secondary: "secondary",
  tertiary: "ghost",
  destructive: "destructive",
};

const sizeClass: Record<AppButtonSize, string> = {
  L: "h-touch min-w-touch px-6 text-body",
  M: "h-10 px-4 text-body",
};

export const AppButton = React.forwardRef<HTMLButtonElement, AppButtonProps>(
  (
    {
      variant = "primary",
      size = "M",
      icon,
      loading = false,
      fullWidth,
      className,
      children,
      disabled,
      ...props
    },
    ref,
  ) => (
    <Button
      ref={ref}
      variant={variantMap[variant]}
      size="default"
      aria-busy={loading || undefined}
      disabled={disabled || loading}
      data-variant={variant}
      data-size={size}
      className={cn(sizeClass[size], fullWidth && "w-full", className)}
      {...props}
    >
      {loading ? (
        <Loader2 className="animate-spin" aria-hidden="true" data-testid="spinner" />
      ) : (
        icon
      )}
      {children}
    </Button>
  ),
);
AppButton.displayName = "AppButton";
