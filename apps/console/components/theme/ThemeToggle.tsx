"use client";

import { Moon, Sun } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { t } from "@/lib/i18n";
import { cn } from "@/lib/utils";
import { applyTheme, readStoredTheme, storeTheme, systemTheme, type Theme } from "./theme";

export interface ThemeToggleProps {
  className?: string;
  /** Controlled value (used by the design gallery); otherwise reads/persists localStorage. */
  value?: Theme;
  onChange?: (theme: Theme) => void;
}

export function useTheme(): [Theme, (t: Theme) => void] {
  const [theme, setThemeState] = useState<Theme>("light");
  useEffect(() => {
    const current = document.documentElement.getAttribute("data-theme");
    setThemeState(current === "dark" ? "dark" : (readStoredTheme() ?? systemTheme()));
  }, []);
  const setTheme = useCallback((next: Theme) => {
    setThemeState(next);
    applyTheme(next);
    storeTheme(next);
  }, []);
  return [theme, setTheme];
}

export function ThemeToggle({ className, value, onChange }: ThemeToggleProps) {
  const [theme, setTheme] = useTheme();
  const current = value ?? theme;
  const next: Theme = current === "dark" ? "light" : "dark";
  const handle = () => {
    if (onChange) onChange(next);
    else setTheme(next);
  };
  return (
    <button
      type="button"
      onClick={handle}
      aria-label={t("theme.toggle")}
      aria-pressed={current === "dark"}
      data-testid="theme-toggle"
      className={cn(
        "inline-flex size-10 items-center justify-center rounded-input border border-border bg-surface text-text-secondary hover:bg-background hover:text-text",
        className,
      )}
    >
      {current === "dark" ? (
        <Sun className="size-5" aria-hidden="true" />
      ) : (
        <Moon className="size-5" aria-hidden="true" />
      )}
    </button>
  );
}
