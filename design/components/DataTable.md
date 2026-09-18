# DataTable

Generic sortable table with loading, empty and error states. Client-side sort by default; controlled sort for server paging.

Source: `apps/console/components/ds/DataTable.tsx` (tests: `DataTable.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `columns` | `DataTableColumn<Row>[]` | id, header, cell?, accessor?, sortable?, numeric?, width? |
| `rows` | `Row[]` |  |
| `rowKey` | `(row) => string` |  |
| `sort / onSortChange` | `DataTableSort` | controlled: table stops sorting client-side |
| `loading` | `boolean` | skeleton rows |
| `error` | `string` | renders ErrorState |
| `onRetry` | `() => void` |  |
| `emptyTitle / emptyHelp / emptyAction` | `` | EmptyState content |
| `onRowClick` | `(row) => void` | rows become focusable, Enter/Space activate |
| `caption` | `string` | sr-only caption |
| `skeletonRows` | `number` | default 5 |

## Variants

- numeric columns right-aligned with tabular figures
- clickable rows

## States

- default
- sorted asc/desc
- loading
- empty
- error (retry)

## Accessibility

- th aria-sort reflects sort state
- Sort buttons labelled 'Sort by <column>'
- Clickable rows are keyboard operable (tabIndex 0, Enter/Space)
- Row count footer

## Tokens used

- `color.surface`
- `color.border`
- `color.background`
- `color.primary`
- `color.text.secondary`
- `radius.card`
- `text.console.body`
- `text.console.small`
- `font.features (tnum)`
