"use client";

import * as React from "react";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { t } from "@/lib/i18n";

export interface AppTextFieldProps extends Omit<React.ComponentProps<"input">, "prefix" | "id"> {
  id?: string;
  label: string;
  helper?: string;
  /** Error message; when set the field is marked invalid and the message replaces the helper. */
  error?: string;
  /** Visual prefix, e.g. "+91" for phone fields. */
  prefix?: React.ReactNode;
  suffix?: React.ReactNode;
  optional?: boolean;
  /** Shorthand: phone fields get the +91 prefix, tel type and numeric input mode. */
  phone?: boolean;
}

export const AppTextField = React.forwardRef<HTMLInputElement, AppTextFieldProps>(
  (
    { id, label, helper, error, prefix, suffix, optional, phone, className, disabled, ...props },
    ref,
  ) => {
    const autoId = React.useId();
    const inputId = id ?? autoId;
    const helperId = `${inputId}-helper`;
    const errorId = `${inputId}-error`;
    const describedBy =
      [error ? errorId : null, helper ? helperId : null].filter(Boolean).join(" ") || undefined;
    const prefixNode = phone ? (prefix ?? "+91") : prefix;

    return (
      <div className={cn("flex flex-col gap-1", className)} data-disabled={disabled || undefined}>
        <label htmlFor={inputId} className="text-small font-semibold text-text-secondary">
          {label}
          {optional ? (
            <span className="ml-1 font-regular text-text-muted">({t("textField.optional")})</span>
          ) : null}
        </label>
        <div
          className={cn(
            "flex items-stretch rounded-input border border-border bg-surface focus-within:ring-2 focus-within:ring-primary",
            error && "border-danger focus-within:ring-danger",
            disabled && "opacity-50",
          )}
        >
          {prefixNode ? (
            <span
              className="tnum flex items-center border-r border-border px-3 text-body text-text-secondary"
              data-testid="prefix"
            >
              {prefixNode}
            </span>
          ) : null}
          <Input
            ref={ref}
            id={inputId}
            disabled={disabled}
            aria-invalid={error ? true : undefined}
            aria-describedby={describedBy}
            type={phone ? "tel" : props.type}
            inputMode={phone ? "numeric" : props.inputMode}
            autoComplete={phone ? "tel-national" : props.autoComplete}
            {...props}
            className={cn("h-11 border-0 bg-transparent focus-visible:ring-0", phone && "tnum")}
          />
          {suffix ? (
            <span className="flex items-center px-3 text-text-secondary">{suffix}</span>
          ) : null}
        </div>
        {error ? (
          <p id={errorId} role="alert" className="text-small text-danger">
            {error}
          </p>
        ) : helper ? (
          <p id={helperId} className="text-small text-text-muted">
            {helper}
          </p>
        ) : null}
      </div>
    );
  },
);
AppTextField.displayName = "AppTextField";
