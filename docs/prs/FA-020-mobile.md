# FA-020 / FA-021 / FA-022 (mobile half) — officer orders, payment collection and khata

Branch `feat/FA-020-agent-orders-mobile`. Requirement IDs: FA-020 (order capture), FA-021
(payment collection), FA-022 (khata view) — mobile halves; the API halves are in
docs/prs/FA-020-api.md, docs/prs/FA-021-api.md and docs/prs/M3-integration.md. Screens A50–A59,
A10 "Collect payment", A22 "New order" / "Collect" / Orders tab / Khata tab.

## Catalogue cache — public API (store mode reuses this)

`packages/core/lib/src/catalog/` (exported from `farmerapp_core.dart`):

| API | What it does |
|---|---|
| `CatalogCache(db, api, {clock})` | the cache; provider `catalogCacheProvider` |
| `refresh({required storeId}) → int` | pulls every page of `GET /v1/catalog/products?store_id=` (products, SKUs, the store's `price_paise`, on-hand `stock_qty`); throws `CatalogUnavailableException` offline and leaves the cache as it was |
| `nearestStore(farmerId, {skuIds}) → NearestStore?` | `GET /v1/stores/nearest`; remembers the farmer's store and stores `available` (on hand − reserved) per SKU with its time; null offline |
| `storeIdForFarmer(farmerId)` | offline answer: remembered nearest store, else the village's `store_id` |
| `search(CatalogQuery) / watchSearch(query)` | active SKUs; every word must match name / brand / active ingredient / a localised name; `category`; `storeId` attaches price (store price, else MRP) and `StockLevel` (`available ?? onHand`, `asOf`); own brand first |
| `item(skuId, {storeId})` | one `CatalogItem` |
| `store(id) / watchStore(id)` | `StoreInfo` (name, code, `catalogRefreshedAt`) |
| `CatalogCache.isStale(refreshedAt, now)` | older than 24 h (stale indicator) |

Tables (Drift v6): `catalog_products`, `catalog_skus`, `catalog_prices` (store × SKU),
`stock_snapshots` (store × SKU, `on_hand`, `available`, `as_of`), `catalog_stores`. The
catalogue is **not** in the sync change feed (checked: `SYNC_ENTITIES` has no product / SKU),
so it is pulled with the read endpoints: on A50 open when online and stale (or never pulled),
and by the refresh action. `HttpCatalogApi` / `FakeCatalogApi` sit on a small
`RestJsonClient` (bearer token, one refresh on 401) shared with payments and khata.

## Orders (FA-020)

- `order` is now a writable sync entity (`orders` + `order_lines`, `OrderCodec`). Create
  payload = `OrderCreate` without prices: `{id (= client_order_id), farmer_id, store_id,
  fulfilment, payment_mode, notes?, lines: [{sku_id, qty}]}`; estimates and display labels live
  under `_local` (never sent; `Outbox.enqueueCreate(..., local:)`).
- Money is server-owned (FA-025): `subtotal/tax/total_paise` stay null until the applied echo
  (`OrderDetailOut`) or a pull; the echo replaces the lines (server ids and prices, labels kept
  by SKU); `order_line` feed rows upsert by id; status changes from pulls drive the A57
  timeline; `events` keep the server history.
- Cart (`cartProvider`): estimates with the server's rule (qty × unit half-up, GST half-up per
  line, total = sum), pickup / delivery.
- Rejections kept on the op: `insufficient_stock` → `StockShortfall` per line from
  `errors[]` (`SyncError.errors` now keeps every entry); A57 "Edit and send again" loads the
  cart with the shortfalls ("Use N"), `OrderRepository.resubmit` folds the new lines into the
  same op id and requeues payments that failed behind it; `sku_not_recommendable` explained.

## Payments (FA-021)

- `payment` is a writable sync entity (`payments`, `PaymentCodec`). Its create payload is
  exactly `PaymentCreate`: **no `id`** (the API forbids extra fields; new
  `SyncEntities.createPayloadWithoutId`) and no amount for an order (server computes it).
- Cash (A55): in-app camera → NF-004 → upload (purpose `receipt`) → op with
  `receipt_uri: upload:<id>` (waits for the upload's `blob_uri`); works offline; shows
  "pending store reconciliation".
- Credit (A56): order placed without a payment mode, then a `payment` credit op (one credit
  gate run). `credit_limit_exceeded` → `CreditBlock` (limit, balance, shortfall, approval
  request id) → "Check approval" requeues the same op (an approved request lets the same order
  through once) or "Collect cash instead".
- UPI QR (A53) / payment link (A54): online only (`POST /v1/payments` after the order is on the
  server); `UpiPoller` polls `GET /v1/payments/{id}` every 3 s ×10, backing off ×1.5 to 10 s,
  stopping at `expires_at` (fake clock + sleep injected); links resend by SMS / WhatsApp.
- A59 collections: today / week (IST), `collected_by` = me or captured here; totals by mode
  count waiting-to-sync cash, pending reconciliation, paid and on khata.
- A57 invoice share: `GET /v1/invoices/{id}/pdf` → `InvoiceSharer` (share_plus in the app,
  WhatsApp picked in the sheet); disabled offline or without an invoice, with the reason.

## Khata (FA-022)

`KhataRepository` fetches **every page** of `GET /v1/farmers/{id}/khata`, merges the entries
and caches the JSON in `khata_snapshots` with the fetch time; A58 shows it offline with "as
of". The balance shown is `KhataView.displayedBalancePaise` = the sum of the entries shown
(asserted in core `khata_test.dart` and agent `order_screens_test.dart`); overdue buckets 0–30 /
31–60 / 61–90 / 90+, due dates with the harvest month, payment history, dues collections not
yet on the ledger, Collect → A52 dues (amount defaults to the balance at the store with the
largest balance, partial allowed up to it).

## Shared files (additive)

`db/app_database.dart` (v6 + migration step), `sync/sync_models.dart` (`order`, `payment`,
`order_line`, `khata_entry`, `createPayloadWithoutId`, `SyncError.errors`),
`sync/outbox.dart` (`local:`; id stripping), `sync/local_entities.dart` (order / payment
codecs, `order_line` refs), `widgets/sync_details_screen.dart` (labels), widgets
`ProductCard` / `CartBar` / `PaymentMethodSelector` / `UpiQrPanel` (real QR via `qr_flutter`) /
`KhataLedger` (new optional props), `utils/format.dart` (`formatMonthYear`),
`farmerapp_core.dart` exports, five ARB files (168 keys × 5), agent `router.dart`,
`main.dart` (HTTP clients + share_plus), `pubspec.yaml` (`share_plus`), home and farmer
profile screens, test harness `AgentDeps` (fakes + overrides). `FakeCommerceServer`
(core, test support) prices orders / checks stock / enforces the credit limit on
`FakeSyncApi`.

## Tests

- core: `test/commerce/catalog_cache_test.dart` (paging, offline search by name / brand /
  ingredient / local name, categories, own brand first, store price vs MRP, stock as of,
  nearest store + village fallback, stale), `order_payment_test.dart` (cart maths, order
  payload, server wins on apply, insufficient stock → resend same op, sku_not_recommendable,
  pulled status / lines, cash offline with receipt, dues, credit exceeded → approval →
  proceeds, UPI create / offline, link resend, UPI polling paid / failed / expiry / network
  with a fake clock, collections totals, `SyncError.errors` round trip), `khata_test.dart`
  (page merge, balance == sum of entries, buckets, offline cache, KhataLedger widget),
  `db/migration_test.dart` (v5 → v6; older-schema fakes drop the v6 tables).
- agent: `test/orders/order_screens_test.dart` (A50–A59, A10 / A22 wiring),
  `order_offline_e2e_test.dart` (offline order + cash → online FakeSyncApi applies both;
  server price wins), goldens A50, A51, A52, A53 waiting / paid / failed, A56, A57, A58 in
  Light / Sunlight; A22 golden and the profile test updated (New order / Collect enabled);
  core UPI panel goldens regenerated (real QR).

## Results

`apps/mobile/tool/check.sh` green: l10n complete (168 new keys × 5), format, analyze (core / agent /
farmer zero issues), string lint, tests 13 (lint) + 489 core (+47) + 129 agent (+21) + 9 farmer.

## Follow-ups

- API: expose the invoice id on `OrderOut` (or `GET /v1/orders/{id}/invoice`); invoices are only
  issued by the POS today, so officer orders show "issued at handover" until then.
- API: credit-approval decisions are not in the change feed and officers cannot list them;
  "Check approval" resends the op. A feed entity (or a notification with the order id) would
  let A56 flip automatically.
- Catalogue refresh on the WorkManager sync run (today: on A50 open when stale / manual).
