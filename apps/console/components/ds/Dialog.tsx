"use client";

import * as React from "react";
import {
  Dialog as DialogRoot,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { useT } from "@/lib/i18n-client";
import { AppButton } from "./AppButton";

export interface DialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  children?: React.ReactNode;
  /** Optional trigger element (wrapped with asChild). */
  trigger?: React.ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  onConfirm?: () => void;
  /** Destructive styling for the confirm action. */
  destructive?: boolean;
  loading?: boolean;
  /** Error shown above the footer (e.g. from a failed mutation). */
  error?: string;
  className?: string;
}

export function Dialog({
  open,
  onOpenChange,
  title,
  description,
  children,
  trigger,
  confirmLabel,
  cancelLabel,
  onConfirm,
  destructive,
  loading,
  error,
  className,
}: DialogProps) {
  const t = useT();
  return (
    <DialogRoot open={open} onOpenChange={loading ? () => {} : onOpenChange}>
      {trigger ? <DialogTrigger asChild>{trigger}</DialogTrigger> : null}
      <DialogContent className={className} closeLabel={t("dialog.close")}>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          {description ? <DialogDescription>{description}</DialogDescription> : null}
        </DialogHeader>
        {children}
        {error ? (
          <p role="alert" className="text-small text-danger">
            {error}
          </p>
        ) : null}
        <DialogFooter>
          <AppButton variant="tertiary" onClick={() => onOpenChange(false)} disabled={loading}>
            {cancelLabel ?? t("common.cancel")}
          </AppButton>
          {onConfirm ? (
            <AppButton
              variant={destructive ? "destructive" : "primary"}
              onClick={onConfirm}
              loading={loading}
            >
              {confirmLabel ?? t("common.confirm")}
            </AppButton>
          ) : null}
        </DialogFooter>
      </DialogContent>
    </DialogRoot>
  );
}
