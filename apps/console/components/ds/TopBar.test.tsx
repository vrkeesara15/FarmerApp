import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { TopBar } from "./TopBar";

describe("TopBar", () => {
  it("renders tenant, search, notifications and profile", () => {
    const onSearchChange = vi.fn();
    const onNotificationsClick = vi.fn();
    render(
      <TopBar
        tenantName="Kisan Agro"
        search=""
        onSearchChange={onSearchChange}
        dateRange={{ start: "2026-09-01", end: "2026-09-17" }}
        onDateRangeChange={() => {}}
        unreadNotifications={3}
        onNotificationsClick={onNotificationsClick}
        user={{ name: "Suresh Patil", role: "Owner" }}
      />,
    );
    expect(screen.getByTestId("tenant-name")).toHaveTextContent("Kisan Agro");
    fireEvent.change(screen.getByRole("searchbox"), { target: { value: "98" } });
    expect(onSearchChange).toHaveBeenCalledWith("98");
    fireEvent.click(screen.getByRole("button", { name: /Notifications/ }));
    expect(onNotificationsClick).toHaveBeenCalled();
    expect(screen.getByTestId("unread-badge")).toHaveTextContent("3");
    expect(screen.getByText("SP")).toBeInTheDocument();
  });
});
