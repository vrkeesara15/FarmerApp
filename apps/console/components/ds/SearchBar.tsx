"use client";

import * as React from "react";
import { Search, X } from "lucide-react";
import { t } from "@/lib/i18n";
import { cn } from "@/lib/utils";

export interface SearchBarProps {
  value: string;
  onChange: (value: string) => void;
  /** Fires on Enter. */
  onSubmit?: (value: string) => void;
  placeholder?: string;
  disabled?: boolean;
  loading?: boolean;
  className?: string;
  id?: string;
  /** Accessible name. */
  label?: string;
}

export function SearchBar({
  value,
  onChange,
  onSubmit,
  placeholder,
  disabled,
  loading,
  className,
  id,
  label,
}: SearchBarProps) {
  const autoId = React.useId();
  const inputId = id ?? autoId;
  return (
    <div
      role="search"
      className={cn(
        "flex h-10 items-center gap-2 rounded-input border border-border bg-surface px-3 focus-within:ring-2 focus-within:ring-primary",
        disabled && "opacity-50",
        className,
      )}
    >
      <Search
        className={cn("size-5 shrink-0 text-text-muted", loading && "animate-pulse")}
        aria-hidden="true"
      />
      <input
        id={inputId}
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter") onSubmit?.(value);
        }}
        placeholder={placeholder ?? t("searchBar.placeholder")}
        aria-label={label ?? t("common.search")}
        disabled={disabled}
        className="h-full w-full bg-transparent text-body text-text placeholder:text-text-muted focus:outline-none [&::-webkit-search-cancel-button]:hidden"
      />
      {value ? (
        <button
          type="button"
          onClick={() => onChange("")}
          aria-label={t("searchBar.clear")}
          disabled={disabled}
          className="rounded-input p-0.5 text-text-muted hover:text-text"
        >
          <X className="size-4" aria-hidden="true" />
        </button>
      ) : null}
    </div>
  );
}
