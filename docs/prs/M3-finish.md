# M3 finish — invoices for every sale, credit approvals in the change feed, store mode on the new contracts

Branch `feat/M3-finish` (from `main` 6fb225e). Requirement IDs: FA-020, FA-021, ST-001, ST-003, ST-007.

PR title: `feat(M3): issue invoices for officer orders, credit approvals in the change feed, and wire store mode to transfer destinations, POS preview and approval retry (FA-020, FA-021, ST-001, ST-003, ST-007)`

## API

### GST invoices for officer / farmer-app orders (ST-001, FA-020 A57)

- `POST /v1/orders/{id}/status` to `handed_over` or `delivered` now issues the order's GST invoice through
  `invoices.service.issue_order_invoice` → `issue_invoice`, the POS path: gapless number per store and
  financial year (`invoice_counter` FOR UPDATE, rolled back with the request), CGST / SGST vs IGST from
  the buyer's state, snapshot and PDF in the blob store.
- Idempotent: an order that already has an invoice (POS sale, earlier transition, retried request) gets
  the same one back; `uq_invoice_order_id` backs it up. Cancelled orders never get one (no transition
  from `cancelled`, and cancel does not issue).
- Lines come from the order as placed (unit price, GST rate). The order total is what was charged
  (payment / khata debit), so the invoice total equals it: the round-off line absorbs the paisa the
  separate CGST / SGST halves may differ by (instead of rounding to the rupee after the money was taken).
- Migration `0017_order_invoice_id` (expand-only): nullable `order.invoice_id` (no FK; `invoice.order_id`
  already points at the order), unique `(tenant_id, invoice_id)`, backfilled from existing invoices.
  `OrderOut` / `OrderDetailOut` / queue items and the `order` sync change payload expose `invoice_id`
  (nullable). Seeded historic orders keep `invoice_no` without an invoice row (`invoice_id` null).

### Credit approvals in the change feed (ST-007, FA-020 A56)

- `credit_approval_request` added to `SYNC_ENTITIES` (server wins; device writes →
  `unsupported_action`). Feed payload = `CreditApprovalOut`.
- Scope (`sync.service.credit_approval_feed_filters`): the user who asked (`requested_by`) and the store
  staff (store manager / accountant) of the request's store. Other officers, farmers and other tenants
  never receive it. (Accountants cannot call `/v1/sync`; the filter is harmless for them.)

### Tests

- `tests/orders/test_order_invoices.py`: officer order → packed → ready → handed_over issues exactly one
  invoice (on the detail, list, change feed; readable and PDF-able by the officer; total = order total,
  intra-state split); repeated transitions 409 and a retried issue return the same invoice; delivered
  gets one, cancelled never; numbering 000001 (POS) / 000002 (order) / 000003 (POS) with no gap.
- `tests/khata/test_credit_feed.py`: pending request reaches the requesting officer, the approval arrives
  as an update from the cursor, store manager sees it; another officer, the farmer and tenant B do not;
  device writes rejected.

## Mobile

### Store mode

- S08 (`stock_transfer_screen.dart`): destinations from `GET /v1/stock/transfer-destinations?from_store_id=`
  (`StoreApi.transferDestinations`, `transferDestinationsProvider`, `TransferDestination`): name ·
  district · distance; 403 `transfer_source_not_allowed` (list or submit) and
  `transfer_destination_not_allowed` (submit; choice cleared, list reloaded) explained.
- S03 (`checkout_screen.dart`): server preview from `POST /v1/stores/{id}/pos/preview`
  (`StoreApi.posPreview` → `GstPreview.fromJson`), asked when S03 opens and 400 ms after cart / buyer
  changes (`PosNotifier.refreshPreview`, stale responses dropped). The local GST computation is kept only
  as the fallback while loading / offline / refused, marked `estimate` and shown with an "Estimate" chip
  and "Preview unavailable offline" note. Cash tender is checked against the server total when present.
- Credit: a 402 keeps `approval_request_id` in `PosState` with the cart; retries send
  `credit_approval_request_id`; "Check approval" reads `GET /v1/credit-approvals?status=approved&farmer_id=`
  and retries the sale when approved, else reports pending / rejected / offline.
- `FakeStoreApi` mimics the server: preview, destinations and 403s, approval requests created on 402,
  pending reused, approved consumed once.

### Officer app

- A56: approvals land in `synced_refs` (entity `credit_approval_request`). When a pull brings one
  `approved`, `SyncEngine` calls `SyncStore.requeueApprovedCredit`: every op rejected with that
  `approval_request_id` is requeued with `credit_approval_request_id` and pushed in the same run — the
  screen flips to "on khata" without a tap. `creditApprovalStateProvider` shows "Approved, sending" /
  "Rejected by the cluster head". "Check approval" stays as the manual fallback and now also sends the id.
- A57: already enabled "Share invoice on WhatsApp" for a non-null `invoice_id` (existing
  `invoicePdf` + `invoiceSharerProvider` path); it now gets the id from pulls. `FakeCommerceServer.handOver`
  emits it; the test goes through a real pull.
- No Drift schema change (approvals use `synced_refs`; `orders.invoice_id` already existed), so no migration.

### Cleanup (docs/prs/ST-001-mobile.md follow-ups)

- Share: store mode's `TextSharer` / `RecordingTextSharer` / `textSharerProvider` / `SharePlusTextSharer`
  removed; S04 shares through the officer `invoiceSharerProvider` (`SharePlusInvoiceSharer`).
- Catalogue: `HttpStoreApi.catalog` pages through the officer `CatalogApi` (`HttpCatalogApi` injected in
  `main.dart`, else built on the same session), so `GET /v1/catalog/products` paging lives once.
- Left on purpose: the PDF link. Store mode keeps `StoreApi.invoicePdfUrl` + `UrlOpener` (it opens the PDF;
  the officer app only shares a link and has no opener), and the `StoreApi` abstraction stays because every
  store test and golden runs against `FakeStoreApi`; routing its invoice calls through `PaymentsApi` would
  only move the call without removing code. The store catalogue is online (store prices, barcode) and is
  not cached in the officer Drift tables.

### Tests

- core `store_providers_test.dart` (debounced preview, server wins, offline / refused estimate; credit
  402 → pending → approved retry with the id → consumed; rejected / offline checks), `http_store_api_test.dart`
  (preview request/response, destinations query + 403, approvals farmer filter), `order_payment_test.dart`
  (approval in the feed resends with the id by itself; rejected not resent; manual recheck sends the id).
- agent `store_pos_test.dart` (approval retry, rejection, server preview, offline estimate),
  `store_ops_test.dart` (destinations endpoint, none, 403 on list / submit), `order_screens_test.dart`
  (A56 flips from the feed, rejection shown, A57 share from a pulled `invoice_id`).
- Goldens regenerated: `s03_checkout_{light,sunlight}.png` only (server preview note and amount in words).

## Results

`SKIP_AUDIT=1 make check` green: API ruff / ruff format / mypy strict (315 files) / bandit, pytest
**2107 passed, 1 skipped**, 96.67 % coverage (was 2102), `export_openapi.py --check` up to date; console
**168** tests (35 files); mobile l10n complete, format, analyze zero issues, string lint 13, core **541**,
agent **190**, farmer **9**; infra terraform fmt + validate (bootstrap, dev, stg, prd). `make openapi`
afterwards leaves openapi.yaml unchanged.
