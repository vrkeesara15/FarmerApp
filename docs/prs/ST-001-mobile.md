# ST-001 (mobile half): tablet store mode with POS and barcode scan, GST invoice share, order queue, stock receipt and transfer, credit approvals and day close (ST-002, ST-003, ST-005, ST-006, ST-007)

## Requirement IDs

- ST-001 (P0) Point of sale + GST invoice: mobile half **done** (API: docs/prs/FA-021-api.md). S02 POS with product grid / search, camera barcode scan (`mobile_scanner`) and manual code entry against `GET /v1/catalog/barcode/{code}`, farmer lookup by phone (walk-in allowed), cart; S03 GST preview; S04 invoice with the server's number, CGST / SGST or IGST, HSN, amount in words, PDF (signed URL) and WhatsApp share (`POST /v1/invoices/{id}/share`) plus the system share sheet (`share_plus`).
- ST-002 (P0) Payment modes: mobile half **done**. UPI QR (QR + polling paid / failed, new QR on failure), card on the existing terminal (reference required), cash (tendered + change), credit (402 `credit_limit_exceeded` -> approval-needed state); S01 / S10 totals by mode from `day-summary`.
- ST-005 (P0) Order queue: mobile half **done**. S05 tabs New / Packing / Ready / Handed over with counts, actions per the server `TRANSITIONS` (invalid ones disabled), cancel with a reason, pull to refresh and a 30 s refresh while visible.
- ST-006 (P0) Day close: mobile half **done**. S10 expected cash, denomination helper, live variance with the threshold warning, deposit slip photo (in-app camera, NF-004, resumable upload), notes, closed state, repeat close (409) handled.
- ST-003 (done, API) now also has UI: S06 stock list (on hand / reserved / available, batches with expiry, 30 / 60-day highlight, filters, search), write-off and adjustment dialogs, S07 goods receipt, S08 stock transfer (FEFO suggested, qty <= available).
- ST-007 (done, API) now also has UI: S09 approvals for cluster heads (approve / reject with a note) and the store manager's credit-limit form (₹50,000 cap -> routed to the cluster head).

PR title: `feat(ST-001): tablet store mode with POS and barcode scan, GST invoice share, order queue, stock receipt and transfer, credit approvals and day close (ST-002, ST-003, ST-005, ST-006, ST-007)`

Branch `feat/ST-001-store-mode-mobile`. Only `apps/mobile`, `design/`, `docs/` touched. Ownership: `packages/core/lib/src/store/` and `apps/agent/lib/screens/store/` are new; nothing is imported from the officer order / payment packages being built concurrently (`catalog`, `orders`, `payments`, `khata`). Shared files got additive edits only: ARB files (+245 keys at the end), `router.dart` (one import, `AppRoutes.store`, `...storeRoutes()`), `main.dart` (four overrides), `otp_screen.dart` (store roles go to S01), `settings_screen.dart` (A63 store-mode tile), `farmerapp_core.dart` (six exports), `auth_api.dart` (`FakeAuthApi` gains optional `role` / `storeId`, default unchanged), agent `pubspec.yaml` (+ `mobile_scanner`, `share_plus`, `url_launcher`).

## What changed

### Core — `packages/core/lib/src/store/`

- `store_models.dart`: `StoreBrief`, `CatalogItem` (from `ProductWithSkusOut` + `SkuOut` or `BarcodeLookupOut`), `StockBatch`, `StockRow` (per SKU, FEFO batches, on hand / reserved / available, `isLow` at `lowStockThreshold` = 10, `expiryBand`), `ExpiryBand` (expired / 30 / 60 days), `StockFilter`, `CartLine`, `SaleMode` (wire values), `PosSaleRequest`, `Invoice` / `InvoiceLine`, `PaymentCreated`, `PaymentStatus`, `PosSaleResult`, `OrderStatus` + `orderTransitions` (copy of the server table) + `canTransition`, `QueueTab`, `queueActions`, `QueueOrder`, `CreditApproval`, `DayClose`, `DaySummary`, `ReceiptLine`, `BatchQty`, `WriteOffReason`, `StockWriteResult`.
- `store_calc.dart` (pure): `GstPreview` (mirrors `invoices/gst.py`: per-line CGST / SGST at half the rate each, half-up, IGST inter-state, round-off half-up to the rupee), `gstRateLabel`, `noteDenominationsPaise`, `denominationTotal`, `cashVariance`, `varianceOverThreshold` (default ₹500), `cashChange`, `parseRupees`, `validateReceiptLine`, `validateBatchQty`, `validateTransfer` (same batch counted once), `suggestFefo` (never an expired batch), `istBusinessDate`, `storeManagerCreditCapPaise`.
- `store_api.dart`: `StoreApi` (every call returns `StoreResult<T>`, never throws; `StoreFailure` carries status, problem code and the body extras such as `shortfall_paise`), `HttpStoreApi` (bearer + one refresh on 401, cursors followed, `Idempotency-Key` on writes, transport errors and 502/503/504 = offline, resumable photo upload over `/v1/uploads` with per-chunk SHA-256, purpose `receipt`).
- `fake_store_api.dart`: `FakeStoreApi` with a realistic Kondapur store (8 SKUs incl. own brands, batches expiring in 20 / 51 days and one expired, 6 queue orders, 2 approvals, a day summary of ₹38,750) mimicking the server rules (transitions, card reference, credit gate, one close per day, qty <= available, manager cap).
- `store_access.dart`: `StoreRole` (none / manager / accountant / clusterHead) with capabilities matching the API role lists (`POS_ROLES`, `STOCK_WRITE_ROLES`, `CLOSE_ROLES`, `APPROVER_ROLES`, `CREDIT_LIMIT_ROLES`), `storeUserProvider` (login-flow session, else the stored one), `storeRoleProvider`, `storeTwoPaneBreakpoint` = 700 dp.
- `store_providers.dart`: `storeApiProvider`, platform seams `UrlOpener` / `TextSharer` / `BarcodeScanner` (recording fakes by default), `storePhotoProcessorProvider` (NF-004), `storesProvider` / `activeStoreProvider` (explicit choice, else the user's store, else the first listed; nothing is fetched for roles without store mode), `daySummaryProvider`, `orderQueueProvider`, `storeCatalogProvider`, `stockRowsProvider`, `creditApprovalsProvider`, `storeFarmerNamesProvider`, `invoiceProvider(id)`; `PosNotifier` (cart, scan, buyer lookup, checkout phases: editing / submitting / offline / referenceRequired / cashShort / awaitingUpi / upiFailed / approvalNeeded / failed / done; the connectivity check happens before the request so an offline sale never leaves the tablet and the cart is kept; UPI polled every 3 s until paid / failed; `retryUpi` asks a new QR for the same order); `DayCloseNotifier` (denominations, coins, notes, camera -> NF-004 slip, upload once, close, 409 -> alreadyClosed).

### Agent app — `apps/agent/lib/screens/store/`

`store_shell.dart` (`StoreShell`: role gate, NavigationRail >= 700 dp / drawer below, store switcher, offline + read-only banners; `StoreResultView`, `StoreCard`, `StoreAmountRow`, `StoreChip`, label helpers), `store_routes.dart` (`/store`, `/store/pos`, `/store/pos/checkout`, `/store/invoice/:id`, `/store/queue`, `/store/stock`, `/store/stock/receipt`, `/store/stock/transfer`, `/store/credit`, `/store/day-close`), `store_home_screen.dart` S01, `pos_screen.dart` S02 (+ `CartPanel`), `checkout_screen.dart` S03 (+ `StoreModeSelector`), `gst_invoice_view.dart`, `invoice_screen.dart` S04, `order_queue_screen.dart` S05, `stock_screen.dart` S06 + `stock_adjust_dialog.dart`, `goods_receipt_screen.dart` S07, `stock_transfer_screen.dart` S08, `credit_screen.dart` S09, `day_close_screen.dart` S10, `store_platform.dart` (`MobileScannerBarcodeScanner` full-screen camera page, `LauncherUrlOpener`, `SharePlusTextSharer`).

Role gating: store managers and accountants land on S01 after the OTP (A04 continue); cluster heads keep the field flow and open store mode from A63 (read-only, plus S09 approvals); field officers (and every other role) never see the A63 tile, and `/store/*` shows "Store mode is not available" without calling the store API.

Reuse: `ProductCard`, `CartBar`, `UpiQrPanel`, `OwnBrandBadge`, `StatTile`, `OfflineBanner`, `EmptyState`, `ErrorState`, `Skeletons`, `AppButton`, `AppTextField`. `PaymentMethodSelector` has no card-terminal option, so S03 uses `StoreModeSelector` with the same look (changing the shared enum would break the officer screens being built in parallel).

### i18n, design

+245 ARB keys (`store*`) in en / te / kn / hi / mr with real translations; `build/untranslated.json` = `{}`. `design/screens/S01.md` .. `S10.md`.

## Design decisions / assumptions

- **No invoice preview endpoint** exists: S03 shows a local preview computed with the server's rule (same half-up rounding, split and round-off; asserted in `store_calc_test.dart` against hand-computed values) and labels it; the issued invoice (number, tax, words) is the server's and is what S04 shows, prints and shares.
- **Online-first**: POS, queue moves, stock writes and the close require the network; the tablet never queues them. A brief drop shows the offline state with everything kept (cart, count, form).
- **Farmer lookup** is local (Drift `farmers` by `+91` phone; the API has no phone search). A number not on the tablet is sent as `farmer_phone` so the server matches or treats it as a walk-in. Credit needs a known farmer.
- **Low stock** = available <= 10 units per SKU until the product master has reorder levels (ST-004).
- **Variance warning** uses the tenant default ₹500; the server applies the tenant's own threshold and flags / notifies.
- **Queue** fetches all open statuses plus handed over / delivered (`status=` repeated) and filters tabs locally so the counts come from one call.

## Follow-ups (API, not in this branch)

- `GET /v1/catalog/stores` shows a store manager only their own store, so S08 has no destination for them (it says so: "No other store is available to you. Ask your cluster head."). Needs a transfer-destination list for store managers.
- POS credit approval: the server assigns the POS order id per attempt and approvals are matched on `order_id`, so a sale retried after approval may be refused again; `PosSaleIn` should accept a client order id or the `approval_request_id`.
- An invoice preview endpoint (or `dry_run` on POS sales) would make S03 authoritative instead of mirrored.
- `UpiQrPanel` still paints the placeholder pattern (shared widget; `qr_flutter` is already a dependency).

## Tests

- Core `test/store/`: `store_calc_test.dart` (GST split, IGST, round-off, denominations, variance threshold, rupee parsing, IST date, receipt / transfer validation, FEFO, stock rows and filters, transitions, roles), `http_store_api_test.dart` (request shapes of barcode, POS, credit 402 extras, queue cursors + statuses, status / transfer / receipt / write-off / credit limit / day close, offline mapping, chunked upload), `store_providers_test.dart` (active store, cart, barcode found / not found / offline, farmer lookup, offline sale blocked with the cart kept, card reference, cash change, UPI polling + new QR, credit exceeded, day close slip / variance / repeat close / offline).
- Agent `test/store/`: `store_access_test.dart` (store manager and accountant land on S01, field officer never sees store mode and `/store` is refused without API calls, cluster head read-only via A63, S01 numbers, two panes at 800 x 1280, phone CartBar + drawer), `store_pos_test.dart` (scan found / not found, manual entry, cart totals, filters, buyer lookup, card reference required -> invoice -> WhatsApp / PDF / share sheet, cash change, UPI polled until paid, UPI failed -> new QR, credit exceeded, walk-in credit disabled, offline blocked with the cart kept), `store_ops_test.dart` (queue counts / allowed and blocked transitions / cancel reason / 409 / 30 s refresh / read-only; stock expiry highlight and filters, write-off qty <= available with photo, adjustment, accountant read-only; receipt validation + submit; transfer FEFO + qty <= available + destination; approvals approve / reject; manager cap; day close variance, threshold, slip, close, repeat close 409, closed state).
- Goldens `test/goldens/store_golden_test.dart`: `s01_store_home`, `s02_pos`, `s03_checkout`, `s05_order_queue`, `s06_stock`, `s10_day_close` at 800 x 1280 in Light and Sunlight (12 new PNGs; existing goldens unchanged).

Results: `cd apps/mobile && ./tool/check.sh` green — pub get, codegen, no untranslated messages, format clean, analyze zero issues (core / agent / farmer), string lint OK (13 self-tests), flutter test core **497**, agent **143**, farmer **9** passed on the branch; after rebasing onto main 11e2f74 (officer A50–A59): core **531**, agent **180**, farmer **9**.

## Integration with the officer order / payment branch (rebase onto 11e2f74)

- ARB: union of both key sets (168 officer + 245 store keys, no duplicates, `untranslated.json` = `{}`); `main.dart` keeps both override blocks; agent `pubspec.yaml` keeps `share_plus` once plus `mobile_scanner` / `url_launcher`; lockfile regenerated; progress rows keep the newest status of each.
- Name clashes in the core exports were resolved on the store side: `CatalogItem` -> `StoreItem`, `CartLine` -> `StoreCartLine`, `parseQty` -> `parseStoreQty` (officer names untouched).
- No Drift tables were added by store mode, so the schema stays at the officer branch's v6.
- Duplication kept on purpose: the officer branch now has a catalogue client (`catalog/`, cached in Drift) and an invoice sharer (`invoiceSharerProvider`); store mode keeps its own online `StoreApi` (store-priced catalogue, barcode, POS) and `TextSharer` / `UrlOpener`. Merging them onto `RestJsonClient` / the officer catalogue cache is a follow-up.

## Checklist

- [x] Tests first, no weakened tests; `./tool/check.sh` green
- [x] Strings in ARB (5 languages), string lint clean
- [x] Money in paise, `formatInr`; IST dates
- [x] No hidden tracking; camera only in-app (no gallery)
- [ ] Human gate: native-speaker review of the new translations (NF-008); on-device scan test with real packs
