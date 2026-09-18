import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { LOCALE_STORAGE_KEY, setLocale } from "@/lib/i18n";
import en from "@/messages/en.json";
import te from "@/messages/te.json";
import { TopBar } from "./TopBar";

function renderBar(extra: Partial<React.ComponentProps<typeof TopBar>> = {}) {
  return render(
    <TopBar
      tenantName="Kisan Agro"
      search=""
      onSearchChange={() => {}}
      dateRange={{ start: "2026-09-01", end: "2026-09-17" }}
      onDateRangeChange={() => {}}
      user={{ name: "Suresh Patil", role: "Owner" }}
      {...extra}
    />,
  );
}

describe("TopBar", () => {
  beforeEach(() => {
    localStorage.clear();
    act(() => setLocale("en", { persist: false }));
  });
  afterEach(() => {
    localStorage.clear();
    act(() => setLocale("en", { persist: false }));
  });

  it("renders tenant, search, notifications and profile", () => {
    const onSearchChange = vi.fn();
    const onNotificationsClick = vi.fn();
    renderBar({ onSearchChange, onNotificationsClick, unreadNotifications: 3 });
    expect(screen.getByTestId("tenant-name")).toHaveTextContent("Kisan Agro");
    fireEvent.change(screen.getByRole("searchbox"), { target: { value: "98" } });
    expect(onSearchChange).toHaveBeenCalledWith("98");
    fireEvent.click(screen.getByRole("button", { name: /Notifications/ }));
    expect(onNotificationsClick).toHaveBeenCalled();
    expect(screen.getByTestId("unread-badge")).toHaveTextContent("3");
    expect(screen.getByText("SP")).toBeInTheDocument();
  });

  it("profile menu lists the five languages in their own script and switches live", () => {
    renderBar();
    expect(screen.queryByTestId("profile-menu")).toBeNull();
    fireEvent.click(screen.getByTestId("profile-menu-trigger"));
    const items = screen.getAllByRole("menuitemradio");
    expect(items.map((el) => el.getAttribute("lang"))).toEqual(["en", "te", "kn", "hi", "mr"]);
    expect(items.map((el) => el.textContent)).toEqual([
      `English${en.language.en}`,
      `తెలుగు${en.language.te}`,
      `ಕನ್ನಡ${en.language.kn}`,
      `हिन्दी${en.language.hi}`,
      `मराठी${en.language.mr}`,
    ]);
    expect(screen.getByTestId("locale-en")).toHaveAttribute("aria-checked", "true");

    fireEvent.click(screen.getByTestId("locale-te"));
    // Same render tree, no reload: labels are Telugu now and the choice is persisted.
    expect(screen.queryByTestId("profile-menu")).toBeNull();
    expect(screen.getByTestId("profile-menu-trigger")).toHaveAttribute(
      "aria-label",
      te.topbar.profile,
    );
    expect(screen.getByRole("searchbox")).toHaveAttribute(
      "placeholder",
      te.topbar.searchPlaceholder,
    );
    expect(document.documentElement.lang).toBe("te");
    expect(localStorage.getItem(LOCALE_STORAGE_KEY)).toBe("te");

    fireEvent.click(screen.getByTestId("profile-menu-trigger"));
    expect(screen.getByTestId("locale-te")).toHaveAttribute("aria-checked", "true");
    expect(screen.getByTestId("locale-en")).toHaveAttribute("aria-checked", "false");
  });

  it("profile menu closes on Escape and offers sign out when wired", () => {
    const onSignOut = vi.fn();
    renderBar({ onSignOut });
    fireEvent.click(screen.getByTestId("profile-menu-trigger"));
    expect(screen.getByTestId("profile-menu")).toBeInTheDocument();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByTestId("profile-menu")).toBeNull();

    fireEvent.click(screen.getByTestId("profile-menu-trigger"));
    fireEvent.click(screen.getByTestId("sign-out"));
    expect(onSignOut).toHaveBeenCalledTimes(1);
    expect(screen.queryByTestId("profile-menu")).toBeNull();
  });
});
