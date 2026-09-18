## Requirement IDs

- FA-021 (P0) Payment collection — API half: UPI dynamic QR, payment link by SMS / WhatsApp, cash with receipt photo (`pending_reconciliation` until the day close), card on the store terminal, credit through the khata ledger port; `GET /v1/payments/{id}` for A53 polling; `payment` sync create for offline cash / credit. Mobile screens left.
- SEC-023 (P0) Webhook HMAC + replay window — done: HMAC-SHA256 over the raw body (constant time), bad signature 401 + stored attempt, replay window (tenant-configurable, default 5 min) 400 `webhook_stale`, idempotent by `(provider, event_id)`, amounts cross-checked against the payment row (mismatch flags the event, never pays), amounts always recomputed server-side on collection.
- ST-001 (P0) Point of sale + GST invoice — API half: `POST /v1/stores/{id}/pos/sales`, gapless invoice numbers per store and financial year, CGST / SGST vs IGST, round-off, amount in words, PDF (fpdf2) in the blob store, share by WhatsApp / SMS. Mobile / tablet screens left (barcode lookup is the catalog agent's `GET /v1/catalog/barcode/{code}`).
- ST-002 (P0) Payment modes — API half: all five modes and `GET /v1/stores/{id}/day-summary?date=` (totals by mode, counts, waiting, failed, refunds, expected cash). Screens left.
- ST-006 (P0) Day close — API half: `POST /v1/stores/{id}/day-close` (expected cash, variance, deposit slip, reconciles the day's cash; over threshold notifies auditors and emits `CashVarianceDetected`), one close per store and date, cluster-head reopen. Screen left.
- Groundwork: FM-010 (webhook -> khata credit in one transaction chain), OPS-008 (`jobs reconcile-payments`), VA-E10 (event hook).

## What changed

**Migration `0013_payments_invoices`** (`down_revision = "0011"`, branch label `payments`; the parent merges it with the orders branch's head). Expand-only: `payment.status` widened (24) with `pending_reconciliation`; target CHECK relaxed (`farmer_id` alone = dues payment before its credit entry); new nullable payment columns `provider_order_id`, `qr_payload`, `short_url`, `expires_at`, `day_close_id`, `failure_reason`; `webhook_event.status` gains `flagged` / `rejected`; `day_close` gains `status` (closed / reopened), `reopened_by/at`, `reopen_reason`, `variance_flagged`; new `invoice` (immutable snapshot, CHECKs for total and tax split, unique number per tenant, one per order) and `invoice_counter` (per store + financial year), both with RLS. Downgrade never deletes money rows (the old target CHECK comes back `NOT VALID`).

**Packages**
- `farmerapp/payments/`: `providers.py` (`PaymentProvider` protocol; `RazorpayProvider` over the Razorpay REST shapes — `/v1/payments/qr_codes`, `/v1/payment_links`, `/v1/settlements/recon/combined`, basic auth — pointed at docker/mockserver locally; `CashfreeProvider` skeleton, PG API 2023-08-01 shapes and its base64 HMAC webhook signature, unit-tested against a fake transport, **not wired**; `FakePaymentProvider`), `service.py` (collection), `webhooks.py` (route + `apply_webhook_event`), `worker.py` (`payment.webhook` handler), `publisher.py` (Pub/Sub REST publisher, recording publisher), `ports.py` (`LedgerPort`), `events.py` (bus), `day_close.py` (summary, close, reopen), `sync_ops.py`, `reconcile.py` (OPS-008), `config.py` (tenant keys, GST state codes, IST).
- `farmerapp/invoices/`: `models.py`, `gst.py` (pure tax maths), `words.py` (Indian numbering), `numbering.py` (gapless counter), `pdf.py` (fpdf2), `ports.py` (`OrderPort`), `service.py` (POS sale, issue, share), `router.py`.
- Shared files, additive only: `api/app.py` (routers + `app.state.payments`), `worker/dispatch.py` (`on_payment_webhook` -> handler), `sync/service.py` + `sync/router.py` (`payment` create before the write-path gate; `OpContext.payments`), `db/models/__init__.py`, `settings.py` (Razorpay secrets, `PAYMENT_PROVIDER`, `PAYMENT_WEBHOOK_DELIVERY`, `PAYMENT_QR_TTL_SECONDS`, prd guard rails), `jobs/cli.py` (`reconcile-payments`), `tests/conftest.py` (`PAYMENT_PROVIDER=fake`), `tests/authz/test_matrix.py` (raw signed-body fixtures + fixtures for the 10 new operations), `tests/auth/test_settings.py` (prd secrets), docker/mockserver (`/razorpay/settlements?date=`, `/razorpay/v1/settlements/recon/combined`, QR pay helper, notes on simulated payments), `.env.example`.
- Dependencies: `fpdf2` (runtime, pure Python), `pypdf` (dev, PDF text in tests).

## Ports (the orders branch plugs in here; no orders / khata / stock code is imported for writes)

| Port | Where | Contract | Default |
|---|---|---|---|
| `LedgerPort.check_and_reserve_credit` | `payments/ports.py` | exactly `farmerapp.khata.credit.check_and_reserve_credit(session, *, tenant_id, farmer_id, store_id, amount_paise, order_id, actor) -> CreditDecision(allowed, approval_request_id, shortfall_paise)` | `KhataLedgerPort` imports the module lazily; missing -> 503 `credit_unavailable` |
| `LedgerPort.post_credit` | `payments/ports.py` | exactly `farmerapp.khata.ledger.post_credit(session, *, tenant_id, farmer_id, store_id, amount_paise, ref_type, ref_id, actor) -> KhataEntry` | lazily imported; missing -> appends the same credit `khata_entry` (`ref_type = payment`) itself |
| `OrderPort.create_pos_order(session, PosOrderDraft) -> Order` | `invoices/ports.py` | persist a priced, taxed `pos` order (status `handed_over`) and take the stock out | `LedgerOrderPort`: `order` + `order_line`, FEFO `sale` movements through `stock.ledger.apply_movement` (409 `insufficient_stock`); replace via `app.state.pos_orders` |

`actor` is `farmerapp.db.audit.Actor` (the request's bound actor; `system_actor(tenant)` in the worker). **No stub files were created** (`farmerapp/khata/credit.py` / `ledger.py` do not exist on this branch); tests inject a `FakeLedger` / fake `OrderPort`, and one test installs fake `farmerapp.khata.credit` / `.ledger` modules to prove the default port delegates with the exact keyword set.

## Events (in-process bus `farmerapp.payments.events.bus`)

| Event | When | Fields | Subscriber |
|---|---|---|---|
| `PaymentCaptured` | an order payment is in hand: webhook `paid`, or cash / card / credit at collection (not for dues: their khata credit is posted in the same transaction) | tenant, payment, order, store, farmer, mode, amount, provider event id, at | orders branch: move the order to `placed` / `reserved` |
| `CashVarianceDetected` | day close with \|variance\| > `day_close_variance_threshold_paise` | tenant, day close, store, business date, expected, counted, variance, threshold, closed by, at | M4 VA-E10 |

Handlers run after the flush; a failing handler is logged and swallowed.

## FM-010 "payment updates balance within 1 min of webhook" — the path

Razorpay -> `POST /v1/webhooks/razorpay` (verify, store `webhook_event`, publish `payment.webhook`; < 100 ms) -> Pub/Sub push -> worker `handle_payment_webhook` -> one transaction: payment `paid` + `post_credit` (khata credit) -> commit. The balance is `sum(khata_entry)` so it moves at that commit; no batch step. Budget: Pub/Sub push latency is sub-second at our volume, the worker transaction is a handful of rows; the SLO monitor is "99.9 % within 2 min, any message in DLQ" (SPEC 12.1, OPS-004). A message that arrives before the API transaction committed raises and is retried by Pub/Sub. Locally (`PAYMENT_WEBHOOK_DELIVERY=inline`) the same function runs inside the webhook request.

## Human gates / follow-ups

- Real Razorpay keys and webhook secret (Secret Manager), webhook URL registration, WhatsApp templates `payment_link` / `invoice_share` and the DLT SMS templates.
- Tenant GSTINs (`gstin_by_state`) and legal name: placeholders until the owner enters them.
- Invoice share links are 15-minute signed URLs (SEC-016); a longer-lived share page is an M5 item.
- Pub/Sub publisher auth token provider for stg / prd (seam `token_provider`) lands with the worker deployment.

## Tests

- `tests/payments/test_providers.py` — HMAC on raw bytes, parsing and normalisation, Razorpay request shapes (auth, QR / link / settlements), error wrapping, Cashfree skeleton + signature, money conversions, fake provider, Pub/Sub publisher, prd guard rails, tenant settings.
- `tests/payments/test_collect_api.py` — server amounts and `amount_mismatch`, already paid / cancelled, QR notes, link by SMS / WhatsApp, walk-in phone, provider failure leaves nothing, dues full / partial / over / nothing due, cash receipt validation, dues cash posts the khata credit, card reference + `PaymentCaptured`, credit via the port (allowed / blocked / dues / walk-in / service missing), farmer UPI-only, store scope.
- `tests/webhooks/test_razorpay_webhook.py` — paid once, duplicate id, second event cannot pay twice, bad / missing signature (stored, genuine still accepted), unknown tenant, replay window + tenant override, amount mismatch flagged, failed then captured, dues capture moves the balance (system actor), lookup by provider ids, ignored / malformed events, Pub/Sub hand-off + worker idempotency + poison / not-yet-visible messages, publish failure 503.
- `tests/webhooks/test_mockserver_e2e.py` (`integration`) — QR created over HTTP on the mockserver, webhook signed by the mock's simulator, replayed byte for byte -> paid.
- `tests/invoices/test_gst.py` — intra / inter split, rounding to the paisa and the rupee, nil-rated seeds, amounts in words (lakh / crore), financial year, number format, Indian grouping.
- `tests/invoices/test_numbering.py` — two committed sessions: second waits on the lock and gets the next number; a rolled-back sale gives its number back.
- `tests/invoices/test_pos_api.py` — intra sale (order `pos` / `handed_over`, stock out, payment = invoice total, PDF text has GSTIN / HSN / number / totals, phone masked), inter-state IGST PDF, sequential numbers with a failed sale in between, walk-in + WhatsApp share, SMS share to the farmer, validation and scope, fake `OrderPort` + credit blocked.
- `tests/dayclose/test_day_close_api.py` — totals by mode (credit excluded from money received), close reconciles cash, 409 repeat, over-threshold notifies every auditor + event, tenant threshold, reopen (cluster head yes, manager 403) and re-close updates the row, validation, IST business day.
- `tests/payments/test_sync_and_ports.py` — offline cash / credit applied, duplicate and conflict, UPI `requires_network`, stale amount rejected, updates still unsupported, default ledger port fallback and delegation, reconciliation mismatches + accountant notifications, CLI.
- Authz matrix: the 10 new operations with fixtures (webhook with a signed raw body).

Results: see docs/progress.md.
