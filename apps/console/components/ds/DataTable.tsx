"use client";

import * as React from "react";
import { ArrowDown, ArrowUp, ArrowUpDown } from "lucide-react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useT } from "@/lib/i18n-client";
import { cn } from "@/lib/utils";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { Skeleton } from "./Skeleton";

export type SortDirection = "asc" | "desc";

export interface DataTableColumn<Row> {
  id: string;
  header: string;
  /** Cell renderer; defaults to `accessor` value. */
  cell?: (row: Row) => React.ReactNode;
  /** Value used for default rendering and client-side sorting. */
  accessor?: (row: Row) => string | number | null | undefined;
  sortable?: boolean;
  /** Right-align numeric columns (also applies tabular figures). */
  numeric?: boolean;
  className?: string;
  width?: string;
}

export interface DataTableSort {
  columnId: string;
  direction: SortDirection;
}

export interface DataTableProps<Row> {
  columns: ReadonlyArray<DataTableColumn<Row>>;
  rows: ReadonlyArray<Row>;
  rowKey: (row: Row) => string;
  /** Controlled sort; when omitted the table sorts client-side using `accessor`. */
  sort?: DataTableSort;
  onSortChange?: (sort: DataTableSort) => void;
  loading?: boolean;
  /** Error message; renders ErrorState with retry. */
  error?: string;
  onRetry?: () => void;
  emptyTitle?: string;
  emptyHelp?: string;
  emptyAction?: React.ReactNode;
  onRowClick?: (row: Row) => void;
  /** Accessible table caption (visually hidden). */
  caption?: string;
  skeletonRows?: number;
  className?: string;
}

function compare(a: unknown, b: unknown): number {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (typeof a === "number" && typeof b === "number") return a - b;
  return String(a).localeCompare(String(b), "en-IN", { numeric: true });
}

export function DataTable<Row>({
  columns,
  rows,
  rowKey,
  sort,
  onSortChange,
  loading,
  error,
  onRetry,
  emptyTitle,
  emptyHelp,
  emptyAction,
  onRowClick,
  caption,
  skeletonRows = 5,
  className,
}: DataTableProps<Row>) {
  const t = useT();
  const [internalSort, setInternalSort] = React.useState<DataTableSort | undefined>();
  const activeSort = sort ?? internalSort;

  const toggleSort = (col: DataTableColumn<Row>) => {
    if (!col.sortable) return;
    const next: DataTableSort = {
      columnId: col.id,
      direction: activeSort?.columnId === col.id && activeSort.direction === "asc" ? "desc" : "asc",
    };
    if (onSortChange) onSortChange(next);
    if (!sort) setInternalSort(next);
  };

  const sortedRows = React.useMemo(() => {
    if (!activeSort || onSortChange) return rows; // server-side when controlled
    const col = columns.find((c) => c.id === activeSort.columnId);
    if (!col?.accessor) return rows;
    const acc = col.accessor;
    const dir = activeSort.direction === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => compare(acc(a), acc(b)) * dir);
  }, [rows, activeSort, columns, onSortChange]);

  if (error)
    return (
      <ErrorState
        title={t("dataTable.error")}
        detail={error}
        onRetry={onRetry}
        className={className}
      />
    );

  return (
    <div
      className={cn("rounded-card border border-border bg-surface", className)}
      data-testid="data-table"
      aria-busy={loading || undefined}
    >
      <Table>
        {caption ? <caption className="sr-only">{caption}</caption> : null}
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            {columns.map((col) => {
              const isSorted = activeSort?.columnId === col.id;
              const Icon = isSorted
                ? activeSort.direction === "asc"
                  ? ArrowUp
                  : ArrowDown
                : ArrowUpDown;
              return (
                <TableHead
                  key={col.id}
                  style={col.width ? { width: col.width } : undefined}
                  aria-sort={
                    isSorted
                      ? activeSort.direction === "asc"
                        ? "ascending"
                        : "descending"
                      : undefined
                  }
                  className={cn(col.numeric && "text-right", col.className)}
                >
                  {col.sortable ? (
                    <button
                      type="button"
                      onClick={() => toggleSort(col)}
                      className={cn(
                        "inline-flex items-center gap-1 rounded-input hover:text-text focus-visible:ring-2 focus-visible:ring-primary",
                        col.numeric && "flex-row-reverse",
                      )}
                      aria-label={t("dataTable.sortBy", { column: col.header })}
                    >
                      {col.header}
                      <Icon
                        className={cn("size-3.5", isSorted ? "text-primary" : "text-text-muted")}
                        aria-hidden="true"
                      />
                    </button>
                  ) : (
                    col.header
                  )}
                </TableHead>
              );
            })}
          </TableRow>
        </TableHeader>
        <TableBody>
          {loading ? (
            Array.from({ length: skeletonRows }, (_, r) => (
              <TableRow key={`s-${r}`} data-testid="skeleton-row">
                {columns.map((col) => (
                  <TableCell key={col.id}>
                    <Skeleton className={cn("h-4", col.numeric ? "ml-auto w-16" : "w-3/4")} />
                  </TableCell>
                ))}
              </TableRow>
            ))
          ) : sortedRows.length === 0 ? (
            <TableRow className="hover:bg-transparent">
              <TableCell colSpan={columns.length} className="p-0">
                <EmptyState
                  title={emptyTitle}
                  help={emptyHelp ?? t("dataTable.empty")}
                  action={emptyAction}
                  className="rounded-none border-0"
                />
              </TableCell>
            </TableRow>
          ) : (
            sortedRows.map((row) => (
              <TableRow
                key={rowKey(row)}
                onClick={onRowClick ? () => onRowClick(row) : undefined}
                tabIndex={onRowClick ? 0 : undefined}
                onKeyDown={
                  onRowClick
                    ? (e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          onRowClick(row);
                        }
                      }
                    : undefined
                }
                className={cn(onRowClick && "cursor-pointer")}
              >
                {columns.map((col) => (
                  <TableCell
                    key={col.id}
                    className={cn(col.numeric && "tnum text-right", col.className)}
                  >
                    {col.cell ? col.cell(row) : (col.accessor?.(row) ?? t("common.none"))}
                  </TableCell>
                ))}
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
      {!loading && sortedRows.length > 0 ? (
        <p className="tnum border-t border-border px-3 py-2 text-small text-text-muted">
          {t("dataTable.rowCount", { n: sortedRows.length })}
        </p>
      ) : null}
    </div>
  );
}
