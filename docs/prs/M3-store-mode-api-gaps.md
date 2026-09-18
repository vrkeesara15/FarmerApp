# M3 store-mode API gaps — ST-001, ST-003, ST-007

Branch `fix/M3-store-mode-api-gaps` (from `main` 54cd2d9). Three gaps found while building
tablet store mode. API and docs only; the mobile screens adopt the contracts below.

## 1. Transfer destinations (ST-003)

`/v1/catalog/stores` scopes a store manager to their own store (unchanged), so the transfer
screen had no destination list.

### `GET /v1/stock/transfer-destinations`

Roles: `store_manager`, `accountant`, `cluster_head`, `owner`, `director`, `tenant_admin`
(`auditor`, `field_officer`, `agronomist`, `farmer`: 403 `forbidden`).

Query: `from_store_id` (optional uuid) — the origin store.

| Caller | Origin | Destinations |
|---|---|---|
| store manager | always their own store (`from_store_id` may repeat it; any other store is 403 `transfer_source_not_allowed`) | the other live stores of that store's cluster (a store without a cluster: none) |
| cluster head | `from_store_id` (must be in their cluster, else 404), else none | the other live stores of their cluster |
| accountant | `from_store_id` (any tenant store), else own store if placed, else none | the origin's cluster; not placed and no origin: every tenant store |
| owner / director / tenant admin | `from_store_id`, else none | every other live store of the tenant |

Response `200`:

```json
{
  "from_store_id": "7c1e…",            // null when there is no origin
  "items": [
    {
      "id": "…", "code": "KNR", "name": "FCC Karimnagar", "district": "Karimnagar",
      "cluster_id": "…",
      "distance_m": 84321.7             // metres from the origin (straight line); null without an origin
    }
  ]
}
```

Order: nearest first (then code); without an origin, by code. Deleted stores and other tenants
never appear.

### `POST /v1/stock/transfers` (changed for store managers only)

- `from_store_id` other than the manager's own store: **403 `transfer_source_not_allowed`**
  (was 404).
- `to_store_id` a live store of the tenant that is not in the set above (another cluster):
  **403 `transfer_destination_not_allowed`**. Unknown / deleted / other-tenant store: 404 as
  before; the same store: 422 as before.
- Cluster head / owner / director keep their previous scope (source in their scope,
  destination any tenant store).

## 2. Credit approvals honoured on retry (ST-007)

Acceptance "sale beyond limit blocked without approval" also means *with* an approval the sale
goes through. Approvals used to match only on the order id of the blocked attempt; the POS
(and any retry without the same client order id) creates a fresh id per attempt, so an
approved sale was refused again.

### New optional request field `credit_approval_request_id` (uuid)

| Endpoint | Where |
|---|---|
| `POST /v1/stores/{id}/pos/sales` | top level of the body (next to `payment`) |
| `POST /v1/orders` and the `order` sync op `create` payload | top level of `OrderCreate` |
| `POST /v1/payments` and the `payment` sync op `create` payload | top level of `PaymentCreate` (mode `credit` only; ignored otherwise) |

Client flow:

1. Credit sale beyond the limit -> **402 `credit_limit_exceeded`**; the problem body carries
   `approval_request_id`, `shortfall_paise`, `balance_paise`, `limit_paise` (sync ops:
   `error.errors[0].approval_request_id`). Keep `approval_request_id` with the cart.
2. A cluster head approves it (`POST /v1/credit-approvals/{id}/approve`; poll
   `GET /v1/credit-approvals?status=approved&farmer_id=…` or wait for the approver).
3. Retry the same sale with `credit_approval_request_id = approval_request_id`.
   - Request is `approved`, same tenant, farmer and store, not yet consumed, and its
     `amount_paise` >= the new credit amount -> the sale goes through (201) and the request
     becomes **`consumed`** (`consumed_at`, `consumed_by_order_id`, `used_at`).
   - Otherwise the normal limit check applies: within the limit it passes without touching
     the request; beyond it -> 402 again. While the named request is still `pending` (same
     farmer and store) that same request is refreshed and returned, so retrying before the
     decision does not pile up requests; a consumed / rejected / mismatched one gets a new
     pending request.
4. One approval authorises exactly one sale: a second use is 402.

The old match on the same order id (client-supplied `id` on `POST /v1/orders`, a sync op's
`entity_id`, a payment for the same order) still works and now also consumes the request.

`CreditApprovalOut` (`GET /v1/credit-approvals`, approve / reject responses) gains
`consumed_at` and `consumed_by_order_id`; `status` may be `consumed` (filterable with
`?status=consumed`). A consumed request cannot be approved or rejected (409
`approval_not_pending`).

Gate contract: `khata.credit.check_and_reserve_credit(…, approval_request_id=None)` — new
optional keyword; `payments.ports.LedgerPort` passes it through.

### Migration `0016_credit_approval_consumption` (down_revision `0015`)

Expand-only: `credit_approval_request.status` CHECK gains `consumed`; nullable
`consumed_at` / `consumed_by_order_id` (no FK: the gate runs before the order row exists);
`(status = 'consumed') = (consumed_at IS NOT NULL)`; `used_at` allowed on `approved` or
`consumed`; index `(tenant_id, consumed_by_order_id)`. Rows already used under 0012
(`approved` + `used_at`) become `consumed`. Downgrade turns `consumed` back into `approved` +
`used_at`; nothing is deleted.

## 3. Server-side invoice preview (ST-001)

### `POST /v1/stores/{id}/pos/preview`

Roles: `store_manager` (own store; another store 404), `accountant`. Body: exactly the POS
sale body (`PosSaleIn`). Response `200` `PosPreviewOut` (values illustrative):

```json
{
  "store_id": "…", "farmer_id": "…",
  "seller_name": "…", "seller_gstin": "36…", "seller_state": "Telangana", "seller_state_code": "36",
  "buyer_name": "…", "buyer_gstin": null, "buyer_state": "Telangana", "place_of_supply": "Telangana (36)",
  "supply_type": "intra",
  "taxable_paise": 90000, "cgst_paise": 2250, "sgst_paise": 2250, "igst_paise": 0,
  "tax_paise": 4500, "round_off_paise": 0, "total_paise": 94500,
  "amount_in_words": "Rupees …",
  "lines": [ { "sl": 1, "sku_id": "…", "description": "…", "hsn": "31051000", "qty": "3",
               "unit": "pc", "unit_price_paise": 30000, "taxable_paise": 90000,
               "gst_rate_bp": 500, "cgst_rate_bp": 250, "cgst_paise": 2250,
               "sgst_rate_bp": 250, "sgst_paise": 2250, "igst_rate_bp": 0, "igst_paise": 0,
               "total_paise": 94500 } ]
}
```

Same computation as the sale (`invoices.service.draft_sale` -> `gst.compute_invoice`; the
sale now calls the same function), so the fields equal the invoice the sale returns. Nothing
is written: no order, stock movement, invoice number (`invoice_counter` untouched), credit
check or payment; stock and DX-007 label claims are checked by the sale only (409
`insufficient_stock`, 422 `sku_not_recommendable`). Errors as
the sale: 404 `farmer_not_found`, 422 `unknown_sku`, 422 `invalid_mode` (credit for a walk-in
buyer), 422 validation. The tablet should call it on cart changes (debounced) and show its
totals instead of computing GST locally.

## Tests

- `tests/stock/test_transfer_destinations.py` — every allowed role's list (cluster, nearest
  first, distances), deleted stores and tenant B excluded, forbidden roles, store without a
  cluster, store-manager transfers within the set (201), to another cluster (403), from
  another store (403), unknown (404) / same store (422) / deleted destination (404); cluster
  head and owner keep their scope. `tests/stock/test_movements.py`: manager's foreign source
  is now 403.
- `tests/khata/test_credit_retry.py` — blocked without approval; pending retry refreshes the
  same request; approved + retried with the id -> through once, consumed by that order; a
  second reuse -> blocked; larger amount -> blocked; another farmer / store -> blocked; unknown
  id; the gate without an order id; `order` sync op re-captured with the approval.
- `tests/invoices/test_pos_preview_and_retry.py` — preview == sale (intra CGST/SGST with
  paise round-off, inter IGST), preview writes nothing and is repeatable, validation, roles,
  scope; POS credit sale 402 carries `approval_request_id`, retry with it -> 201 once, reuse
  402; credit payment retried with the approval for a re-captured order.
- `tests/khata/test_credit.py` — the gate signature contract gains `approval_request_id`.
- Authz matrix: fixture for the preview route; the destinations route runs for every role.

Results (TEST_* on `farmerapp_test_gaps`, `--timeout=120 -x`): 2102 passed, 1 skipped, 96.66 % coverage; ruff check, ruff format --check, mypy strict, `export_openapi.py --check`, bandit green (was 2053 passed at M3 integration).

## The stalled full run

The first full coverage run stalled at about 36 % (around
`tests/authz/test_matrix.py::test_role_matrix[GET /v1/catalog/stores-*]`, a plain read that
none of this change touches) with no query running in Postgres; it was killed after two hours.
A rerun with `-o faulthandler_timeout=90` finished in 16 min (2102 passed, 1 skipped) with no
test over 90 s, so the stall did not reproduce and is not in the new code paths (no FOR UPDATE
is taken by the preview; approval consumption locks only in the request's own session).
Most likely mechanism: asyncpg awaiting a half-open socket of a pooled connection (the test
engine had no connect / statement timeout, so even the pre-ping can wait forever).
Guards: the test engine now sets `connect_args={"timeout": 30, "command_timeout": 120}`
(a stalled statement or ping raises), and `pytest-timeout` (dev dependency, `timeout = 300`
in `[tool.pytest.ini_options]`) fails a stalled test with a traceback instead of hanging.
