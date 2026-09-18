export type Theme = "light" | "dark";
export const THEME_STORAGE_KEY = "farmerapp.console.theme";
export const THEME_ATTRIBUTE = "data-theme";

export function readStoredTheme(): Theme | null {
  try {
    const v = window.localStorage.getItem(THEME_STORAGE_KEY);
    return v === "dark" || v === "light" ? v : null;
  } catch {
    return null;
  }
}

export function storeTheme(theme: Theme): void {
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    /* storage unavailable (private mode, blocked) — theme is still applied for this page */
  }
}

export function applyTheme(theme: Theme): void {
  document.documentElement.setAttribute(THEME_ATTRIBUTE, theme);
}

export function systemTheme(): Theme {
  try {
    return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  } catch {
    return "light";
  }
}

/** Inline script (runs before hydration) so the first paint uses the persisted theme. */
export const themeInitScript = `(function(){try{var t=localStorage.getItem(${JSON.stringify(THEME_STORAGE_KEY)});if(t!=="dark"&&t!=="light"){t=window.matchMedia&&window.matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light"}document.documentElement.setAttribute("data-theme",t)}catch(e){document.documentElement.setAttribute("data-theme","light")}})();`;
