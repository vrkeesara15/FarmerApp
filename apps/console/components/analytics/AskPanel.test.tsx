import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { setAuthToken, setCurrentUser } from "@/lib/api";
import { handleAnalytics } from "@/lib/mock/analytics";
import { SessionProvider } from "@/lib/session-context";
import { AskPanel } from "./AskPanel";

vi.mock("next/navigation", () => ({ usePathname: () => "/home" }));

/** Routes `fetch` at the in-app analytics mock, the same contract Playwright uses. */
function installAnalyticsFetch() {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = new URL(String(input), "http://localhost");
    const method = (init?.method ?? (init?.body ? "POST" : "GET")).toUpperCase();
    const path = url.pathname.replace(/^\/api\/mock\/v1\//, "").split("/");
    const body = init?.body ? (JSON.parse(String(init.body)) as Record<string, unknown>) : {};
    const res = handleAnalytics(method, path, url.searchParams, { id: "u-owner", role: "owner" }, body);
    if (!res) return new Response("not mocked", { status: 404 });
    return new Response(JSON.stringify(res.json), {
      status: res.status,
      headers: { "content-type": "application/json", ...res.headers },
    });
  });
}

function renderPanel() {
  installAnalyticsFetch();
  setAuthToken("mock-access-owner-1");
  setCurrentUser({
    id: "u-owner",
    tenant_id: "t1",
    phone: "+919000000001",
    name: "Owner",
    role: "owner",
    store_id: null,
    cluster_id: null,
    language: "en",
    status: "active",
  });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <SessionProvider>
        <AskPanel />
      </SessionProvider>
    </QueryClientProvider>,
  );
}

const ask = (question: string) => {
  fireEvent.change(screen.getByTestId("ask-input"), { target: { value: question } });
  fireEvent.click(screen.getByTestId("ask-submit"));
};

afterEach(() => {
  vi.restoreAllMocks();
  setAuthToken(null);
});

describe("AN-016 Ask panel", () => {
  it("answers with rows and the SQL, labelled as generated and read-only", async () => {
    renderPanel();
    ask("Which officers had fewer than 3 verified visits?");

    const answer = await screen.findByTestId("ask-answer");
    expect(answer).toHaveTextContent("verified visits");
    expect(await screen.findByTestId("data-table")).toBeInTheDocument();

    const sql = screen.getByTestId("ask-sql");
    expect(sql).toHaveTextContent("SQL used");
    expect(sql).toHaveTextContent("read-only against authorised views");
    expect(sql.querySelector("pre")).toHaveTextContent("v_officer_week");
  });

  it("shows 'I could not answer that' with the reason instead of an error", async () => {
    renderPanel();
    ask("What is the weather on Mars?");

    const refusal = await screen.findByTestId("ask-could-not-answer");
    expect(refusal).toHaveTextContent("I could not answer that");
    expect(refusal).toHaveTextContent(/officer, store, farmer, referral and mandi-price views/);
    expect(screen.queryByTestId("ask-answer")).toBeNull();
    expect(screen.queryByTestId("ask-sql")).toBeNull();
  });

  it("refuses a question carrying a phone number", async () => {
    renderPanel();
    ask("What did 9876543210 buy?");

    const refusal = await screen.findByTestId("ask-could-not-answer");
    expect(refusal).toHaveTextContent("personal details");
  });

  it("will not submit a question shorter than three characters", async () => {
    renderPanel();
    fireEvent.change(screen.getByTestId("ask-input"), { target: { value: "hi" } });
    expect(screen.getByTestId("ask-submit")).toBeDisabled();
  });

  it("lists the authorised views so nobody has to guess", async () => {
    renderPanel();
    await waitFor(() => expect(screen.getByTestId("ask-views")).toBeInTheDocument());
    expect(screen.getByTestId("ask-views")).toHaveTextContent("v_mandi_price_latest");
  });
});
