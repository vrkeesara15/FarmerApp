# FA-020 (API half) — order capture, order queue, stock movements, credit limits, khata

Branch `feat/FA-020-orders-stock-credit`. Requirement IDs: FA-020, ST-005 (API done, mobile
pending), ST-003, ST-007 (done), FA-022 (API done, mobile view pending).

## Shared functions (the payments package codes against these exact signatures)

### `farmerapp/khata/credit.py`

```python
async def check_and_reserve_credit(
    session: AsyncSession,
    *,
    tenant_id: UUID,
    farmer_id: UUID,
    store_id: UUID,
    amount_paise: int,
    order_id: UUID | None,
    actor: Actor,
) -> CreditDecision

@dataclass(frozen=True)
class CreditDecision:
    allowed: bool
    approval_request_id: UUID | None
    shortfall_paise: int
    khata_entry_id: UUID | None = None   # additive: the debit posted when allowed
    balance_paise: int = 0               # additive: balance at the store before the sale
    limit_paise: int = 0                 # additive: the farmer's limit at the store
```

`Actor` is `farmerapp.khata.ledger.Actor = User | farmerapp.db.audit.Actor` (the request's
user, or an audit actor for jobs / webhooks). Behaviour, in the caller's transaction:

1. Locks the farmer row `FOR UPDATE` (concurrent credit sales of one farmer serialise).
2. An **approved, unused** `credit_approval_request` for the same farmer, store and
   `order_id` with `amount_paise >=` the sale lets it through once (`used_at` set).
3. Else allowed when `khata_balance(farmer, store) + amount_paise <= limit` (the
   `credit_limit` row; no row = 0). Exactly at the limit is allowed.
4. **Allowed ⇒ the gate posts the khata debit itself** (`ref_type = "order"`,
   `ref_id = order_id`, `due_date` = the farmer's next expected harvest, else today +
   `credit_due_days`). Callers must not post a second debit; use
   `decision.khata_entry_id` for `payment.khata_entry_id`.
5. Not allowed ⇒ a `pending` request (or the pending one for the same `order_id`,
   refreshed) is written and returned with `shortfall_paise > 0`. **Nothing is raised.**
   Answer 402 `credit_limit_exceeded` by *returning* the problem response
   (`problem_response(..., extra=decision_extra(decision))`) — raising would roll back the
   approval request with the request transaction. `CreditLimitExceededError.from_decision`
   exists for places where a rollback is fine.
6. `amount_paise <= 0` (or not an int) raises `ValueError`; an unknown farmer is 404.

A cluster head (own cluster), owner or director decides requests with
`POST /v1/credit-approvals/{id}/approve|reject`; the caller then retries the **same**
`order_id`.

### `farmerapp/khata/ledger.py`

```python
async def post_credit(
    session: AsyncSession,
    *,
    tenant_id: UUID,
    farmer_id: UUID,
    store_id: UUID,
    amount_paise: int,
    ref_type: str,          # "payment" for a collection, "adjustment" for a correction
    ref_id: UUID | None,    # payment.id
    actor: Actor | None,
    note: str | None = None,  # additive, optional
) -> KhataEntry
```

Appends a `credit` row (flushed, not committed) and returns it; `created_by` = the actor's
user id. `amount_paise` must be a positive int and `ref_type` one of `order` / `payment` /
`adjustment`, else 422 `invalid_khata_entry`. `post_debit` (same shape plus `due_date`,
`harvest_month`, `note`, `today`) is its twin; the credit gate uses it.

## Design decisions

- **Reservation = separate table** `stock_reservation` (store, SKU, batch, order, line, qty,
  `active | consumed | released`), not `reserve` / `release` movement kinds: `stock_on_hand`
  and every existing ledger reader stay unchanged; `available = on_hand − active
  reservations` (`stock.ledger.reserved_by_batch` / `reserved_by_sku`). Placing an order
  locks the store's unexpired batches of the SKUs (`FOR UPDATE`) and allocates FEFO
  (earliest expiry, no-expiry last, then oldest receipt); short lines → 409
  `insufficient_stock` with `errors[] = {index, sku_id, requested, available}`. Handover /
  delivery turns reservations into `sale` movements; cancel releases them.
- **Order statuses**: placing writes `placed` then `reserved` (two `order_status_event`
  rows). `TRANSITIONS`: placed → reserved | cancelled; reserved → packed | cancelled; packed →
  ready | cancelled; ready → handed_over | delivered | cancelled; terminal otherwise.
  `placed → reserved` reserves stock (seeded / pre-FA-020 orders); a line without a
  reservation at handover is sold FEFO.
- **Prices** are always recomputed (`prices_for` + MRP fallback, product GST, half-up per
  line). A client `unit_price_paise` / `expected_total_paise` that differs → 409
  `amount_mismatch` with the server numbers; money fields are strict ints.
- **Channels**: officer → `officer` (own farmers only), farmer login → `farmer_app` (self),
  store manager / accountant → `pos` at their own store (any farmer of the tenant).
- **Nearest store** = the farmer's village store, else the closest store to the village by
  `ST_Distance`; orders without `store_id` go there.
- **Transfers are atomic** (`transfer_out` + `transfer_in` in one transaction, same batch
  number / expiry / cost, shared `ref_id`); no in-transit state for the pilot.
- **Outbound stock writes** (transfer, write-off, count) may only take unreserved stock; more
  is 409 `negative_stock` with the batch's available quantity.
- **Credit limits**: tenant settings `store_manager_max_credit_limit_paise` (default
  5,000,000 = ₹50,000) and `credit_due_days` (default 90) are read by
  `khata.ledger.CreditSettings` (kept in the khata package to avoid touching the shared
  settings model). Above the cap a store manager gets 403
  `credit_limit_needs_cluster_head`.
- **Cancelling a credit order** posts the reversing credit (`ref_type = adjustment`,
  `ref_id = order.id`); the ledger stays append-only.
- **Khata view**: `open_debits` settles credits FIFO by due date per store; buckets
  `0_30` (1–30 days past due), `31_60`, `61_90`, `90_plus`; their total equals
  `overdue_paise` when every debit has a due date (all write paths set one).
- **Notifications**: every status change writes `notification(kind = order_status,
  title_key = order.status.title, body_key = order.status.<status>)` for the farmer's login
  and the placing user, never for the actor. The apps own the i18n strings for these keys.
- **Sync**: `order` create is wired (`orders/sync_ops.py`); `order_line`, `payment`,
  `khata_entry` device writes stay `unsupported_action`.

## Tests

- `tests/orders/test_place.py` — FEFO reservation and queue, server-side amounts, per-line
  insufficient stock (expired batches ignored), who orders for whom (officer / farmer /
  store staff / forbidden roles / other tenant), claims and duplicate ids, nearest store,
  the `order` sync op (applied, replay conflict, rejects).
- `tests/orders/test_queue.py` — transition table, pack → ready → handover makes sale
  movements equal to the reservations, notifications, invalid transitions, cancel releases,
  pre-FA-020 placed order, queue scope, append-only status history.
- `tests/stock/test_movements.py` — receipts, transfers, write-offs, adjustments (audit),
  reserved stock protection, and a seeded random-sequence property test (3 seeds × 40 steps)
  asserting `batch.qty == sum(movements) >= 0` per batch after every step and no change on
  a refused step.
- `tests/khata/test_credit.py` — limit caps and scope, harvest-linked debit, cancel reversal,
  402 + approval + single use, approval scope, sync block keeps the request, the
  `check_and_reserve_credit` contract.
- `tests/khata/test_khata.py` — bucket boundaries, FIFO ageing, view (buckets = overdue,
  payment history), manual entries (append-only, audited, validation, roles), the
  `post_credit` contract.
- The authz matrix picks up the 13 new operations (fixtures for the 11 with path parameters
  or bodies); the RLS meta-test covers the three new tables.

Results (TEST DB `farmerapp_test_orders`): full suite 1517 passed, 1 skipped, coverage 96.4 % (one run hit the known transient asyncpg "connection was closed" during seed setup and passed on rerun; `money_columns` count in `tests/catalog/test_models.py` bumped 15 -> 19 for the four approval-request amounts); ruff, format, mypy strict, bandit, `export_openapi.py --check` green.
