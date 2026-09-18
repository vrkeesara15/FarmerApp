# M3 integration — orders / stock / credit + payments / invoices + product master

Requirement IDs touched: FA-020, FA-021, FA-022, ST-001, ST-002, ST-005, ST-006 (API done,
mobile pending); ST-003, ST-007, WC-005, SEC-023 (done); DX-007 guardrail wired.

## Merges

`main` (bbc6b9c, WC-005) <- `feat/FA-020-orders-stock-credit` (f22d8c6) <-
`feat/FA-021-payments-invoices` (65d68e4), two `--no-ff` merge commits (branch history kept);
worktrees and `worktree-agent-*` branches removed, feature branches kept.

Conflicts and how they were resolved:

| File | Resolution |
|---|---|
| `apps/api/README.md` | all sections kept; the auto-merged M3 region was rebuilt from each branch's own section (git had interleaved two code blocks) plus a new "M3 integration" section |
| `tests/authz/test_matrix.py` | fixtures of all three branches kept |
| `db/models/__init__.py` | `Invoice`, `InvoiceCounter` and `CreditApprovalRequest` all imported |
| `tests/catalog/test_models.py` | money columns recomputed from the merged metadata: **25** = 15 (0011) + 4 `credit_approval_request` (0012) + 6 `invoice` (0013) |
| `tests/orders/test_models.py` | money sync writes: `order` and `payment` create are wired (validation error on an incomplete payload), `order_line` / `khata_entry` still `unsupported_action` |
| `docs/progress.md` | each row takes its newest status |
| `apps/api/openapi.yaml` | regenerated with `make openapi`, never hand-merged |
| `uv.lock` | `uv lock` re-run (no change beyond FA-021's `fpdf2` / `pypdf`) |
| `api/app.py`, `sync/service.py`, `settings.py`, `.env.example` | merged cleanly (both money sync ops wired); checked by hand |

## Migration

`0015_merge_m3_heads` (`alembic merge 0012 0013 0014`, no DDL). `alembic heads` = one head.
Verified on a scratch database: upgrade 0011 -> head, downgrade head -> 0011, upgrade -> head.

## Contracts wired

- **Credit (ST-007 x FA-021).** `payments.ports.KhataLedgerPort` now calls
  `khata.credit.check_and_reserve_credit` / `khata.ledger.post_credit` directly; the lazy
  import, the 503 `credit_unavailable` path and the self-written fallback entry are gone.
  `create_payment` asks the gate before writing anything; allowed -> the gate's debit becomes
  `payment.khata_entry_id` (no second debit); blocked -> `CreditBlocked` is returned and
  `POST /v1/payments` answers 402 `credit_limit_exceeded` via
  `khata.credit.credit_blocked_response` (shared with `POST /v1/orders`), so the
  `credit_approval_request` commits. The `payment` sync op rejects with the same 402 and
  keeps the request (same shape as the `order` op). A credit payment for an order that was
  already *placed* on credit (its debit is on the khata) is 409 `already_paid` instead of a
  second debit.
- **POS credit.** The POS asks the gate for the invoice total with a pre-assigned order id
  *before* writing the order, invoice or stock: a refused sale leaves only the approval
  request (402), an allowed one passes the decision to `create_payment`.
- **Dues.** Paid dues (cash / card / webhook) post their khata credit through the real
  `post_credit` (`note = "Payment received"`, system actor from the worker).
- **POS orders.** `invoices.ports.OrderPort` stays the seam (`app.state.pos_orders`); the
  default is now `orders.pos.OrdersPosPort`: DX-007 check, FEFO via
  `stock.service.allocate_fefo` (unexpired batches only), reservations held and consumed by
  `consume_order` into `sale` movements, one `order_status_event`. `LedgerOrderPort`
  (models written directly) was removed.
- **Payment events.** The bus gained `subscribe_async` / `dispatch(session, event)`: writing
  subscribers run in the payment's transaction inside a savepoint (a failing one is logged
  and rolled back; the payment still commits). `farmerapp.orders.payment_events` subscribes
  to `PaymentCaptured`: a fully paid order waiting in `placed` moves to `reserved`
  (system actor, farmer + placing user notified). Orders placed with `payment_mode`
  `upi_qr` / `payment_link` are now *prepaid*: stock is held at placing but the order waits
  in `placed` until the payment is captured. Registered by `create_app` and the worker's
  `payment.webhook` handler.
- **DX-007.** `orders.service.assert_lines_recommendable` calls
  `catalog.recommendable.assert_sku_recommendable` for every line with a `label_claim_id`
  (REST order, `order` sync op, POS `lines[].label_claim_id` — new optional field): 422
  `sku_not_recommendable` with `errors[].loc = ["lines", i, "label_claim_id"]` (was
  `invalid_order`).

## Tests added / changed

- `tests/payments/test_order_payment_flow.py` — order (UPI, prepaid) -> farmer's UPI QR ->
  signed webhook -> Pub/Sub hand-off -> worker handler -> payment `paid` -> order
  `reserved` (reservation kept, not doubled) -> notification for the farmer's login and the
  officer; redelivery idempotent; reserved orders untouched; a failing subscriber never
  un-pays; an order placed on credit cannot be debited again; `register()` idempotent.
- `tests/payments/test_collect_api.py` — credit through the real gate (one debit, linked);
  blocked = 402 and the `credit_approval_request` row persists with the request running in a
  savepoint that rolls back on a raise (`request_transactions`, production semantics).
- `tests/payments/test_sync_and_ports.py` — offline credit beyond the limit rejected, request
  kept; default port = the khata contract (real validation, real debit).
- `tests/webhooks/test_razorpay_webhook.py` — dues webhook: one credit entry from
  `post_credit`, balance == signed sum of entries.
- `tests/invoices/test_pos_api.py` — fake `OrderPort` + real gate (pre-assigned order id, one
  debit); blocked POS credit = 402 with no order / invoice / stock / debit; default port
  goes through the orders service (consumed reservations, sale movements, status event,
  DX-007 good and bad claim).
- `tests/orders/test_place.py` — `sku_not_recommendable` for a claim of another SKU, a draft
  claim (REST) and a retired claim (`order` sync op).
- `tests/payments/helpers.py` — `SpyLedger` (real port + call log) replaces `FakeLedger`;
  the pay world gives its farmer a credit limit.
- `tests/test_db_pool.py` — the flake regression test (below).

## The dropped-connection flake

Symptom (M3-kickoff and FA-020 full runs): a test failed in *setup* with asyncpg
"connection is closed" / "connection was closed in the middle of operation", once in an
uploads authz-matrix case; reruns passed.

Findings:
- Since M2 the suite shares one session-scoped app-role engine (`tests/conftest.py`,
  `pool_size=2`), so pooled connections outlive every test. Unlike the production engine
  (`db/session.get_engine`, `pool_pre_ping=True`) it had no pre-ping: a pooled connection
  that died between tests was handed to the next test's `db_session` / `world` setup.
- What killed them: `farmerapp-db-1` had been **recreated** (container `Created` ==
  `StartedAt` == 17:01:48 UTC, after a clean shutdown, image unchanged since 04:39) while the
  three M3 branches were being tested in parallel worktrees. Every checkout shares the
  compose project `farmerapp` (`name:` in docker-compose.yml) and `make db` ran
  `docker compose up -d --build`: any config difference between checkouts (most likely the
  git-ignored `.env`, absent in a worktree, so `DB_PORT` 5432 vs 5434) makes compose recreate
  the shared container, dropping all connections of any suite running elsewhere. The exact
  trigger of that recreate is inferred (Docker keeps no event history that far back); the
  recreate itself is recorded on the container.
- Ruled out: idle drops through Docker Desktop / emulation (4 idle asyncpg connections still
  answered after 2, 5 and 10 minutes), server idle timeouts (`idle_session_timeout` and
  `idle_in_transaction_session_timeout` are 0), a JIT crash of the emulated amd64 image
  (forced JIT queries ran cleanly; no crash in the server log).

Fix:
- Test engine `pool_pre_ping=True` (same as production): a dead pooled connection is
  detected at checkout and the pool reconnects. It only acts at checkout, before a test runs
  a statement; a connection that dies during a test still fails it (no retries).
  `tests/test_db_pool.py` kills every app-role backend server-side between two checkouts:
  it fails without the ping and passes with it.
- `make db` uses `--no-recreate`, so one checkout can no longer replace the running db
  container under another (after changing `docker/postgres` or the port: `make down`).
- Statement-cache / `command_timeout` changes were not needed: no timeout is configured and
  the errors were closed sockets, not stale prepared statements.

## Results

`SKIP_AUDIT=1 make check`: API 2053 passed, 1 skipped (96.6 % coverage; ruff, format, mypy
strict, bandit, openapi --check green); console 168 vitest + lint / typecheck / build; mobile
13 + 455 + 92 + 9 flutter tests, analyze clean; infra fmt / validate (tflint, checkov not
installed locally). API suite run a second time: 2053 passed, 1 skipped, no connection
errors. `make openapi` leaves `openapi.yaml` unchanged.

## Follow-ups

- Mobile / tablet screens for FA-020, FA-021, FA-022, ST-001, ST-002, ST-005, ST-006.
