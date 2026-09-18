import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { installCatalogFetch } from "@/test/mock-fetch";
import { setAuthToken, setCurrentUser } from "@/lib/api";
import { SessionProvider } from "@/lib/session-context";
import { LabelClaimsView } from "./LabelClaimsView";

vi.mock("next/navigation", () => ({ usePathname: () => "/products/label-claims" }));

function renderAs(role: string) {
  installCatalogFetch();
  setAuthToken(`mock-access-${role}-1`);
  setCurrentUser({
    id: `u-${role}`,
    tenant_id: "t1",
    phone: "+919000000008",
    name: "Dr. Kavitha Rao",
    role,
    store_id: null,
    cluster_id: null,
    language: "en",
    status: "active",
  });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <SessionProvider>
        <LabelClaimsView />
      </SessionProvider>
    </QueryClientProvider>,
  );
}

const draftRow = async () =>
  (await screen.findByTestId("claim-status-draft")).closest("tr") as HTMLElement;

afterEach(() => {
  vi.restoreAllMocks();
  setAuthToken(null);
});

describe("C51 label claims editor", () => {
  it("shows Approve only to the agronomist, with the regulatory confirmation", async () => {
    renderAs("agronomist");
    const row = await draftRow();
    fireEvent.click(within(row).getByRole("button", { name: "Approve" }));
    const dialog = await screen.findByRole("dialog");
    expect(dialog).toHaveTextContent("Approval is a regulatory decision");
    expect(dialog).toHaveTextContent("Dr. Kavitha Rao");
    fireEvent.click(within(dialog).getByRole("button", { name: "Approve claim" }));
    await waitFor(() => expect(screen.queryByTestId("claim-status-draft")).toBeNull());
    expect(screen.getAllByTestId("claim-status-approved")).toHaveLength(2);
  });

  it("hides Approve from the owner (human gate stays with the agronomist)", async () => {
    renderAs("owner");
    const row = await draftRow();
    expect(within(row).queryByRole("button", { name: "Approve" })).toBeNull();
    expect(within(row).getByRole("button", { name: "Retire" })).toBeInTheDocument();
  });

  it("read-only roles see approved claims only and no editing actions", async () => {
    renderAs("field_officer");
    await screen.findByTestId("claim-status-approved");
    expect(screen.queryByTestId("claim-status-draft")).toBeNull();
    expect(screen.queryByRole("button", { name: "New claim" })).toBeNull();
  });

  it("validates the editor on the client before calling the API", async () => {
    renderAs("agronomist");
    await draftRow();
    fireEvent.click(screen.getByRole("button", { name: "New claim" }));
    const dialog = await screen.findByRole("dialog");
    fireEvent.click(within(dialog).getByRole("button", { name: "Save draft" }));
    expect(
      await within(dialog).findByText("The CIB&RC source reference is required"),
    ).toBeInTheDocument();
    expect(within(dialog).getByText("Enter whole days, 0 or more")).toBeInTheDocument();
    expect(within(dialog).getByText("Enter a number greater than 0")).toBeInTheDocument();
  });
});
