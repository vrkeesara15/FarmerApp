## Requirement IDs

- M3-KICKOFF (SPEC 14.4) Alembic models for the M3 entities of SPEC 8.2 (`product`, `sku`, `label_claim`, `stock_batch`, `order` / `order_line`, `payment`, `khata_entry`) plus `price_list`, `pest_or_disease`, `stock_movement`, `credit_limit`, `webhook_event`, `day_close`, with RLS, read endpoints, the price resolver, the stock ledger, the khata balance and the M3 demo seed — done
- WC-005 Product master + label claims — data model, `price_for` resolver and read endpoints; claims are `draft | approved | retired` and only approved ones are ever returned to non-maintainers (DX-007 guardrail); console screens and write endpoints left
- FA-022 Khata view — `khata_entry` is append-only and `khata_balance(farmer, store)` is the sum of the ledger; `GET /v1/farmers/{id}/khata` (balance, overdue, next due date, balance per store, credit limits, entries newest first) — read side done, app screen left
- ST-003 Stock movements — append-only `stock_movement` ledger; `stock_on_hand(store, sku)` = sum of movements; `stock_batch.qty` is a cache written in the same transaction by `apply_movement` (never below zero); goods receipt / transfer / damage write paths left
- SEC-023 Webhook HMAC + replay window — `webhook_event` (provider, `event_id` unique per tenant + provider, `signature_ok`, payload, received / processed, status) and `payment.provider_event_id` unique per tenant + provider; HMAC verification and the replay window are the loop's job
- ST-006 Day close — `day_close` (one per store and business date; `variance = counted - expected` CHECK; deposit slip URI)
- ST-007 Credit approval — `credit_limit` (farmer x store, `set_by`, `approved_by`)
- FA-020 / FA-021 / ST-001 / ST-002 / ST-005 — `order` / `order_line` / `payment` models, scope and read endpoints; write flows are the loop's job

## What changed

**Migration `0011_m3_catalogue_stock_orders_payments_khata`** (down_revision `0010`): 14 new tables, nothing existing altered (backward compatible). Every table has the base columns, `enable_rls` (SELECT + INSERT only for `stock_movement` and `khata_entry`, both added to `APPEND_ONLY_TABLES`), FK and lookup indexes, and CHECK constraints for enums, signs and invariants (`order.total = subtotal - discount + tax`, movement sign per kind, `day_close.variance`, payment provider vs mode, `label_claim` approved needs `approved_at`). Money is `bigint` paise everywhere; GST is `gst_rate_bp` (basis points).

**Packages**
- `farmerapp/catalog/{models,pricing,schemas,router}.py` — product master, `pest_or_disease` (designed to be referenced by M6 `corpus_problem`), label claims, `price_for` / `prices_for` / pure `resolve` (store override, then tenant default, latest `effective_from`, validity window; MRP fallback).
- `farmerapp/stock/{models,ledger,schemas,router}.py` — `apply_movement`, `stock_on_hand`, `stock_on_hand_by_sku`, `stock_on_hand_by_batch`, `InsufficientStockError` (409), `InvalidMovementError` (422).
- `farmerapp/orders/{models,schemas,router}.py` — `line_total_paise`, `tax_paise` (half-up to the paisa); `label_claim_id` on a line records why a SKU was recommended.
- `farmerapp/payments/{models,schemas,router}.py` — `payment`, `webhook_event`, `day_close`.
- `farmerapp/khata/{models,schemas,router}.py` — `khata_balance`, `khata_balances_by_store`, `overdue_paise`, `credit_limit`.
- `farmerapp/auth/scope.py` — `STORE_VISIBILITY` / `store_filters` / `visible_store_filters`, `order_filters`, `payment_filters`, `KHATA_VISIBILITY` / `khata_farmer_filters` / `khata_entry_filters`.
- Sync: `order`, `order_line`, `payment`, `khata_entry` are in `SYNC_ENTITIES` with `server_wins` conflict rules and in the changes feed (same scope as their REST reads); device writes are rejected with `unsupported_action` until FA-020 / FA-021 / FA-022 wire them.

**Read endpoints** (all with `x-roles`, cursor pagination, SPEC 2.6 scope, 404 outside scope)

| Route | Roles | Scope |
|---|---|---|
| `GET /v1/catalog/products` (`q`, `category`, `own_brand`, `store_id`) | every role | tenant catalogue; SKUs with resolved price, stock on hand when `store_id` given |
| `GET /v1/catalog/skus/{id}` | every role | label claims approved only, drafts / retired for agronomist + owner |
| `GET /v1/catalog/label-claims` (`crop_id`, `pest_id`, `sku_id`, `status`) | every role | approved only unless agronomist / owner |
| `GET /v1/stores/{id}/stock` (`sku_id`, `expiring_within_days`, `include_empty`) | owner, director, tenant admin, auditor, accountant, cluster head, store manager | own store / own cluster / tenant |
| `GET /v1/orders`, `/v1/orders/{id}` | all but agronomist | store / cluster / tenant; officer the orders they placed; farmer own |
| `GET /v1/payments` | all but agronomist | store / cluster / tenant; officer the ones they collected; farmer own |
| `GET /v1/farmers/{id}/khata` | all but agronomist | SPEC 2.6 khata row (farmer own, officer own farmers, store / cluster / tenant) |

**Seed** (`farmerapp/jobs/seed_catalog.py` static data, `farmerapp/jobs/seed_m3.py` generator, wired through `SeedProfile.m3`). FULL per tenant: 45 products (own brand labelled `FCC` / `GFL`, multi-brand), 78 SKUs with barcodes, HSN and GST, 41 pest / disease rows for the six crops, 140 claims (132 approved, 6 draft and 2 retired for WC-005 review) all with `source_ref = "seed-fixture — replace with CIB&RC data (human gate)"`, price lists (tenant default, store overrides, one expired), stock batches per store with receipts, damage, one transfer and expiries within 30 / 60 days (ST-004), 150 orders over 60 days for fcc (15 for gfl) across POS / officer / farmer app with lines, sale movements, invoices, payments by mode with Razorpay-style webhook events, khata debits and repayments, 8 opening balances overdue > 90 days (VA-F10), credit limits, 3 day closes per store with one shortfall. Both tenants seed in about 2 s (budget 30 s). SMALL (test fixtures): 5 products / 10 SKUs / 5 claims / 1 batch per store / 3 orders / 2 khata entries per tenant. Idempotent (uuid5 ids); SMALL keys and invoices are `s`-prefixed so FULL on top only adds.

**GST check.** The brief said "5 % seeds"; seeds for sowing are nil-rated under the current schedule (HSN 1005 / 1006 / 1202 / 1207 / 1209), so seeds are 0. Fertilisers 5 %, pesticides 18 %, neem-based bio-pesticide 12 %, sprayers 12 %.

## Tests

- `tests/catalog/test_models.py` — money columns are integer `*_paise` (no numeric / float money anywhere), RLS on all 14 tables, price resolver (pure + DB), claim / product / SKU constraints, audit row.
- `tests/catalog/test_read_api.py` — every role lists products; filters; store price + stock equals the ledger; claims approved-only except agronomist / owner (drafts), cross-tenant 404.
- `tests/orders/test_models.py` — stock on hand = sum of movements with batch cache in step, sign rules, insufficient stock; seeded cache = ledger; khata balance = sum of entries (FA-022 groundwork), overdue; append-only grants on both ledgers; RLS; order / payment / webhook / day-close CHECKs and SEC-023 uniqueness; sync rules, rejected writes, changes feed.
- `tests/orders/test_read_api.py` — orders, order detail, payments, khata and stock scope per role (farmer sees only own khata; officer own farmers; store manager own store; cluster head own cluster; agronomist 403).
- `tests/seed/test_seed_m3.py` — FULL counts and plausibility, ledger / totals / balance consistency, DX-007 claim on recommended lines, SMALL counts, idempotency, FULL on SMALL.
- Authz matrix picks up the 8 new operations (fixtures added for the 4 with path parameters; `world` exposes `store_id`, `sku_id`, `order_id`).

Results: see the commit / docs/progress.md.

## Left for the loop

FA-020 order capture with stock reservation, FA-021 / ST-002 payment collection (Razorpay QR / link via mockserver, cash receipt), SEC-023 webhook endpoint with HMAC + replay window, ST-001 POS + GST invoice PDF, ST-003 goods receipt / transfer / damage endpoints (use `apply_movement`), ST-005 queue transitions, ST-006 day-close endpoint, ST-007 limit enforcement, WC-005 console + claim approval (human gate: CIB&RC data).
