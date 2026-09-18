import { fireEvent, render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { DataTable, type DataTableColumn } from "./DataTable";

type Row = { id: string; name: string; visits: number };
const rows: Row[] = [
  { id: "1", name: "Ramesh", visits: 12 },
  { id: "2", name: "Anita", visits: 30 },
  { id: "3", name: "Kiran", visits: 5 },
];
const columns: DataTableColumn<Row>[] = [
  { id: "name", header: "Name", accessor: (r) => r.name, sortable: true },
  { id: "visits", header: "Visits", accessor: (r) => r.visits, sortable: true, numeric: true },
];

const firstCellTexts = () =>
  within(screen.getByRole("table"))
    .getAllByRole("row")
    .slice(1)
    .map((r) => within(r).getAllByRole("cell")[0]!.textContent);

describe("DataTable", () => {
  it("renders rows and sorts client-side", () => {
    render(<DataTable columns={columns} rows={rows} rowKey={(r) => r.id} />);
    expect(firstCellTexts()).toEqual(["Ramesh", "Anita", "Kiran"]);
    fireEvent.click(screen.getByRole("button", { name: "Sort by Visits" }));
    expect(firstCellTexts()).toEqual(["Kiran", "Ramesh", "Anita"]);
    fireEvent.click(screen.getByRole("button", { name: "Sort by Visits" }));
    expect(firstCellTexts()).toEqual(["Anita", "Ramesh", "Kiran"]);
    expect(screen.getByText("3 rows")).toBeInTheDocument();
  });

  it("controlled sort calls back without reordering", () => {
    const onSortChange = vi.fn();
    render(
      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(r) => r.id}
        sort={{ columnId: "name", direction: "asc" }}
        onSortChange={onSortChange}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Sort by Name" }));
    expect(onSortChange).toHaveBeenCalledWith({ columnId: "name", direction: "desc" });
    expect(firstCellTexts()).toEqual(["Ramesh", "Anita", "Kiran"]);
  });

  it("empty, loading and error states", () => {
    const onRetry = vi.fn();
    const { rerender } = render(<DataTable columns={columns} rows={[]} rowKey={(r) => r.id} />);
    expect(screen.getByTestId("empty-state")).toBeInTheDocument();
    rerender(
      <DataTable columns={columns} rows={[]} rowKey={(r) => r.id} loading skeletonRows={3} />,
    );
    expect(screen.getAllByTestId("skeleton-row")).toHaveLength(3);
    rerender(
      <DataTable
        columns={columns}
        rows={[]}
        rowKey={(r) => r.id}
        error="HTTP 500"
        onRetry={onRetry}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Retry" }));
    expect(onRetry).toHaveBeenCalled();
  });

  it("row click", () => {
    const onRowClick = vi.fn();
    render(
      <DataTable columns={columns} rows={rows} rowKey={(r) => r.id} onRowClick={onRowClick} />,
    );
    fireEvent.click(screen.getByText("Anita"));
    expect(onRowClick).toHaveBeenCalledWith(rows[1]);
  });
});
