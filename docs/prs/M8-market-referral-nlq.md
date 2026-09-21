# M8 — mandi prices, farmer referrals, and natural-language questions (FM-012, FM-013, AN-016)

Branch `feat/M8-market-referral-nlq`. SPEC 2.4 (FM-012, FM-013), 5.3 (AN-016), 11.3 SEC-027,
13.3 (farmer app F40 / F70), 2.6 (roles). Builds on docs/prs/M6-diagnosis-api.md (the Claude
client pattern), docs/prs/M7-security-privacy.md (the shared PII guard) and dbt/README.md
(the authorised-view idea, one layer up).

## What landed

| Area | Where |
|---|---|
| Alembic `0042` | `mandi_price`, `referral`, `farmer.referral_code`; the five AN-016 authorised views, the `app_nlq_scope_ok` scope function and the `farmerapp_readonly` role. Both new tables under RLS and audited. **Also a merge revision** — see "Migrations" below. |
| FM-012 port | `farmerapp/market/provider.py`: `MandiPriceProvider` protocol, `DataGovInProvider` (OGD India / Agmarknet), `FakeMandiPriceProvider`, `DisabledMandiPriceProvider`, `build_provider`. |
| FM-012 job | `farmerapp/market/{service,jobs}.py`; `python -m farmerapp.jobs mandi-prices --tenant fcc` (daily 07:30 IST). |
| FM-012 API | `GET /v1/me/mandi-prices`, `GET /v1/farmers/{id}/mandi-prices` (`farmerapp/market/router.py`). |
| FM-012 app | `packages/core/lib/src/market/` + `apps/farmer/lib/screens/advisory/mandi_prices_screen.dart` (F45), reached from F40 My crops. |
| FM-013 API | `farmerapp/referrals/`: `GET /v1/me/referral`, `POST /v1/me/referral/invites`, `POST /v1/me/referral/claim`, `GET /v1/referrals`, `GET /v1/referrals/summary`, `POST /v1/referrals/{id}/reward`; `referral_code` on `POST /v1/farmers`. |
| FM-013 app | `apps/farmer/lib/screens/referral_screen.dart` (F71) from F70 Me, `share_plus` through the `TextSharer` seam. |
| FM-013 console | `app/(console)/referrals/` (C95): per-store roll-up and the recent list with the reward action. |
| AN-016 | `farmerapp/nlq/`: `views.py` (the allowlist and the DDL), `sql_guard.py` (sqlglot validation), `llm.py` (Claude), `service.py` (scope, execution, logging), `router.py`. |
| AN-016 console | `components/analytics/AskPanel.tsx` on C10 owner home. |
| Settings | `MANDI_*`, `NLQ_*` (app); `tenant.settings.mandi` and `tenant.settings.referral`. |

---

## FM-012 mandi prices

### The public source, exactly

`DataGovInProvider` reads the **Open Government Data (OGD) Platform India** resource

> "Current Daily Price of Various Commodities from Various Markets (Mandi)"
> resource id `9ef84268-d588-465a-a308-a864a43d0070`
> <https://data.gov.in/resource/current-daily-price-various-commodities-various-markets-mandi>

published by the Directorate of Marketing & Inspection (DMI), Ministry of Agriculture &
Farmers Welfare — the same figures as **Agmarknet** (agmarknet.gov.in).

* **Licence**: *Government Open Data Licence — India* (GODL,
  <https://data.gov.in/government-open-data-license-india>). It permits commercial re-use
  **with attribution** and without implying endorsement, and it disclaims accuracy. So every
  screen attributes it ("Agmarknet (data.gov.in)") next to the price date, and both apps say
  the prices are indicative. FarmerApp never presents a mandi price as its own quote or as a
  store's offer.
* **Key**: `https://api.data.gov.in` needs a free per-account API key (`MANDI_API_KEY`).
  Registering the account and accepting the licence is a **human gate** (below). Without a
  key `build_provider` returns the disabled provider and the job does nothing — nothing else
  breaks.
* **What leaves the process**: the state, the district and the commodity name, plus the key.
  No farmer, no id, no coordinate (`farmerapp/privacy/egress.py`, entry `data_gov_in`,
  `indian_region=True`). `DataGovInProvider.params` pins the exact query-parameter set and a
  test asserts it.

Rupees per quintal become **integer paise** in the adapter (CLAUDE.md), `arrival_date`
(`DD/MM/YYYY`) becomes the `price_date`, and a row whose max is below its min is repaired
rather than dropped (the feed does this occasionally).

### The daily refresh

`python -m farmerapp.jobs mandi-prices --tenant <id|slug>` walks every **district** the
tenant operates in (store districts ∪ village districts) × every **crop a farmer actually
grows**, asks the provider for each pair and upserts one `mandi_price` row per (market, crop,
variety, grade, price date). Re-running it the same day rewrites the same rows; rows older
than 90 days are dropped. A provider failure for one pair is counted and the rest still land.

The feed has its own commodity vocabulary ("Paddy(Dhan)(Common)"), so
`tenant.settings.mandi.commodities` maps crop code → published names. A crop with no mapping
is asked for by its English name, which is right for Cotton, Maize and Tomato and wrong for
Paddy — **reviewing that mapping against the live feed is a human gate.**

### The reads

`GET /v1/me/mandi-prices?markets=5` (farmer) and `GET /v1/farmers/{id}/mandi-prices` (staff
in scope, or the farmer) return, per crop the farmer grows, the rows of the **latest date we
hold**, nearest market first — same district, then alphabetical. Mandis have no coordinates
in the public feed, so "nearest" is a best effort and the district is what the farmer
recognises anyway.

```json
{
  "farmer_id": "…", "district": "Warangal", "as_of": "2026-09-20",
  "indicative_note_key": "mandi.indicative",
  "crops": [{
    "crop_id": "…", "crop_code": "paddy", "crop_name": "Paddy",
    "crop_names": {"en": "Paddy", "te": "వరి"},
    "price_date": "2026-09-20", "source_name": "Agmarknet (data.gov.in)",
    "source_url": "https://data.gov.in/resource/…",
    "quotes": [{"id": "…", "market": "Warangal", "district": "Warangal",
                "variety": "Common", "grade": "FAQ", "price_date": "2026-09-20",
                "min_price_paise": 205000, "modal_price_paise": 215050,
                "max_price_paise": 225000, "source": "agmarknet",
                "source_name": "Agmarknet (data.gov.in)", "fetched_at": "…"}]
  }]
}
```

A crop we hold no price for is still listed, with `price_date: null` and no quotes, so the
app can say "no price for this crop yet" instead of hiding the crop.

**FM-012's acceptance criterion is "prices shown with date and source"**, so the date and the
source are on the quote, on the crop group and on the payload — an app cannot render a price
without them.

### The farmer app (F45)

`apps/farmer/lib/screens/advisory/mandi_prices_screen.dart`, opened from the F40 My crops
chip (`crops-mandi`). One card per crop, the price date and the source under the crop name,
the markets with modal / min–max per quintal, then the indicative note (with an audio button,
SPEC 13.3 low-literacy rules) and `AsOfLabel`.

**Two dates, on purpose.** The *price date* belongs to the mandi; the *"as of"* belongs to
this phone's cache. A week-old cache therefore never looks like today's price. The screen
works offline from the `KisanCache` snapshot like FM-007 / FM-008.

---

## FM-013 referral

### The model

`farmer.referral_code` is the farmer's own code — 8 characters from an alphabet with no
O/0, I/1 or S/5, minted the first time they open the Refer screen (so no backfill). `referral`
is one row per invitation:

```
pending  ── an invite was shared (optionally to a known phone)
   ↓
attributed ── the invited farmer registered with the code: referrer, invited farmer and the
   ↓          invited farmer's nearest store recorded, with the reward the tenant promised
rewarded  ── a store manager (or tenant admin / owner) confirmed the credit was given
```

Duplicate and self-referral prevention is **structural as well as checked**:

* `uq_referral_invited_farmer` — a farmer is *the invited one* at most once, ever, so a
  concurrent double claim ends in `referral_already_attributed` rather than two credits;
* `uq_referral_pending_phone` — one live pending invite per (referrer, invited phone);
* `ck_referral_not_self` + a service check — a farmer may never refer themself.

No plain phone is stored: a pending invite keeps the SEC-026 `phone_hash` (to match the
registration) and `phone_last4` (so the console can tell which invite it was).

### Who gets credited

The **referrer** and the **invited farmer's nearest store** — the store that will actually
serve the new farmer (`orders.service.nearest_store`: their village store, else the closest).
The reward amounts are snapshotted onto the row at attribution, so changing the rule later
never rewrites history. A tenant with no store yet still credits the referrer.

### The two registration paths

`attribute()` is one code path with one set of rules, reached from two places:

1. **Officer registration** — `POST /v1/farmers` with `referral_code`. A bad code is a
   **warning, never a failed registration**: `attribute_quietly` returns the problem code and
   it comes back in `warnings` (`referral_code_unknown`, `referral_self`, …), with
   `referral_id` set when it worked.
2. **The farmer app** — `POST /v1/me/referral/claim {code}`. The code arrives from the invite
   link, never from typing: **NF-010 forbids a text field on any farmer screen**
   (`apps/farmer/test/no_typing_test.dart` pins the typing routes to phone + OTP). So
   `MarketRepository.rememberCode()` stores what a link carried, and `claimPendingReferral()`
   in `start.dart` claims it on the way in, after the farmer record exists. An offline claim
   keeps the code for the next attempt; any server refusal spends it.

### The farmer app (F71) and the console (C95)

F71 (from F70 Me) shows the code, the counts, and two buttons: the OS share sheet
(`share_plus` behind the `TextSharer` seam — WhatsApp is what the farmer picks there) and an
`sms:?body=` link through the existing `UrlOpener`. Every share also records a `pending`
referral. When the tenant switched referrals off, the buttons are replaced by one line.

C95 (`/referrals`) shows the per-store roll-up and the recent list with the reward action; a
store manager only ever receives their own store's rows, and the list shows four phone digits,
never a number.

### The reward rule is a placeholder

`tenant.settings.referral` = `{enabled, referrer_reward_paise: 0, store_reward_paise: 0,
reward_note: null, claim_window_days: 30}`. **Both amounts are 0 and that is deliberate**: what
a referrer and a store actually get is a commercial decision per tenant (human gate below). A
zero reward still attributes the referral, which is what FM-013 is graded on, and the app says
"your store will tell you what the reward is" rather than promising an amount.

---

## AN-016 natural-language questions

`POST /v1/analytics/ask {question}` for **owner, director and cluster head** (a cluster head
scoped to their own cluster). `GET /v1/analytics/ask/views` returns the catalogue so the
console can show what the assistant can answer from.

### Postgres views, not BigQuery — for now

SPEC 5.3: "for P0 the console reads read-only Postgres replicas for live figures; BigQuery and
dbt arrive in P1". The dbt authorised views (`dbt/models/views/v_*`, AN-013) are the same idea
one layer up, with the same grains, names and scope rules. AN-016 asks the database the
console already reads, so an answer and a dashboard can never disagree; when the console moves
to BigQuery these definitions move with it.

Five views (`farmerapp/nlq/views.py` is the single source for the DDL, the validator allowlist
and the prompt schema):

| View | Grain |
|---|---|
| `v_officer_week` | officer × ISO week: visits, verified, confirmed, farmers, minutes on farm |
| `v_store_day` | store × IST day: fulfilled orders, gross / discount / net paise, farmers served |
| `v_farmer_summary` | farmer: district, acreage, last visit / order, lifetime net |
| `v_referral_store` | store × ISO week: referrals, attributed, rewarded (FM-013) |
| `v_mandi_price_latest` | crop × market × variety × grade, latest date (FM-012) |

### Four independent layers

1. **The role.** The query runs as `farmerapp_readonly` (`SET LOCAL ROLE`), `NOLOGIN
   NOBYPASSRLS`, granted `SELECT` on **these five views and nothing else** — no table, no
   sequence, no other view, and `ALTER DEFAULT PRIVILEGES` never mentions it, so a table
   created later is not reachable either. Tested per table.
2. **The transaction.** `SET LOCAL transaction_read_only = on` plus a `statement_timeout`,
   inside a savepoint that is **always** rolled back — so even a bug in every layer above
   cannot leave a change behind. `session.no_autoflush` keeps application writes out of it.
3. **The view bodies.** Every view filters `tenant_id = app_current_tenant()` (the same
   binding Postgres RLS uses) and calls `app_nlq_scope_ok(cluster_id, store_id)`, which reads
   the caller's scope from two GUCs the request sets. **A cluster head's question returns
   their own cluster whatever SQL the model wrote** — the scope binds the data, not the text.
4. **The validator** (`sql_guard.py`, sqlglot, Postgres dialect), before any of that.

### What the validator rejects

Positive allowlists throughout, so anything new fails closed:

| rule | what it stops |
|---|---|
| one statement | `SELECT 1; DROP TABLE farmer` |
| must be a `SELECT` | every DDL/DML statement, `COPY`, `CALL`, `DO`, `GRANT`, `SET`, `VACUUM` |
| no write node anywhere | `WITH x AS (DELETE FROM … RETURNING *) SELECT * FROM x` — the CTE write a "starts with SELECT" check misses |
| relations in the allowlist | any table, any other view, `pg_catalog`, `information_schema` |
| no schema prefix but `public` | `other_schema.v_officer_week`, `db.schema.table` |
| functions in the allowlist | `pg_read_file`, `dblink`, `lo_import`, `query_to_xml`, `pg_sleep`, `current_setting`, `set_config`, … |
| casts in the allowlist | `'farmer'::regclass` resolves catalogue objects |
| no `INTO` | `SELECT … INTO evil` — a write in `SELECT` clothing |
| no locking clause | `FOR UPDATE` |
| a bounded `LIMIT` | a cartesian product that would run until the timeout |

`ALLOWED_FUNCTIONS` holds **sqlglot's canonical names** (`date_trunc` → `timestamp_trunc`,
`to_char` → `time_to_str`, `string_agg` → `group_concat`); a test pins the mapping so a
sqlglot upgrade that renames one is a failing test, not a question that silently stops working.

### The prompt, and why rows never go back to a model

The prompt carries the question, `views.schema_text()` (view names, grains, column meanings —
**never a row, never a value**), the caller's role and scope *in words* ("cluster head", "one
cluster only" — never an id), and today's date in IST. It goes through the shared SEC-027
guard: `NLQ_PROMPT_FIELDS` in `farmerapp/pii/llm_guard.py` pins the request's shape (adding a
field fails `tests/pii/test_llm_guard.py`), and `guard_prompt` refuses a question carrying a
phone number, an e-mail address or a coordinate — the caller gets "please ask without personal
details", and **nothing reaches the provider**.

The plain-language answer is therefore the model's own `explanation` of what its SQL computes,
completed by the real row count — not a second call that would have to see the data. One
call, one round trip, and the rows go to the caller and to nobody else. Views also carry no
farmer identity (no name, phone, landmark or coordinate; AN-014); `v_officer_week` does carry
`officer_name`, because the spec's own acceptance question is unanswerable without it and the
three roles allowed to ask already see officer names in the console (WC-002).

`ClaudeNlqClient` mirrors the DX-004 client: `anthropic.AsyncAnthropic` built once
(`LazyClaudeNlqClient` defers it so an API without a key still starts), `claude-opus-5` by
default, `output_config={"format": {"type": "json_schema", "schema": …}}` with
`additionalProperties: false` and every field required, `stop_reason` checked before the
content, one retry on `max_tokens` (doubled) and one on an unusable answer.

### Logging (AN-016: "queries logged")

Every attempt is a row in the append-only `llm_call_log` (reused from M6, kept one year). The
last row of each question also carries `parsed.nlq`:

```json
{"question": "…", "sql": "SELECT …", "validation": "accepted|rejected|refused|error",
 "validation_reason": "…", "execution": "ok|failed", "views": ["v_officer_week"],
 "rows": 4, "scope": "one cluster only"}
```

so the question, the generated SQL, the validation outcome and the row count are all on the
record — including for a question that was rejected. Log events: `llm_call`
(`purpose=analytics_ask`), `nlq_asked`, `nlq_sql_rejected`, `nlq_query_failed`,
`nlq_prompt_refused`, `nlq_refusal`.

### Failing well

A refusal, invalid SQL, a rejected relation, a timeout — all come back as **200 with
`answered: false`**, `message_key: "analytics.ask.could_not_answer"` and a readable `reason`,
with the attempted SQL still in `sql` so the reader can see what happened. Only an
unconfigured assistant (`NLQ_LLM=off`) is a 503 `ask_unavailable`. The console panel shows
"I could not answer that" plus the reason, never a red error state.

### The console panel

`components/analytics/AskPanel.tsx` on C10 owner home (owner, director, cluster head): the
question box, the answer, the rows in a `DataTable`, and `<details>` "SQL used" whose first
line says the SQL was **generated by the assistant and run read-only against authorised
views**. A second disclosure lists what the assistant can answer from, so nobody has to guess.

---

## Migrations

`0042_m8_market_referral_nlq`, branch label `m8_extras`, `down_revision = ("0036", "0040")`.

It is **a merge revision as well as an expansion**. `main` carried two heads —
`0036_analytics_segments` and `0040_m7_security_privacy`, both children of `0035` — with no
merge between them, so `alembic upgrade head` (which the pytest harness uses to build its
template database) could not resolve a target. This revision joins them, so the branch has
exactly one head again. A parallel M8 branch that takes `0041` from `0040` will need its own
merge with this one, exactly as the M7 branches did (`0033`, `0034`, `0035`).

Expand-only and backward compatible: two new tables, one nullable column, five views, one
role, one function. The downgrade removes all of it.

Several pre-existing failures on `main` are fixed here too, because `make check-api` has to
pass:

* `tests/test_migrations.py` did not know about `otp_challenge.request_ip` (added by `0040`);
* `GRIEVANCE_*` / `OTP_*` settings from the M7 security branch were undocumented in
  `docs/deploy/configuration.md`;
* `bandit` exited non-zero on four B608 (`hardcoded_sql_expressions`) findings in
  `privacy/export.py` and `retention/sweep.py`, whose identifiers come from reviewed tables
  through `_quote` and whose values are always bound parameters — they now carry a
  `# nosec B608` saying so, as the new `nlq/views.py` DDL does;
* the SEC-006 authz matrix had **42 failures** on the M7 NF-013 routes: the three
  `/v1/admin/data-requests/{id}/…` operations had no `RouteFixture` (so the matrix refused to
  guess their path parameter), and `test_collections_never_contain_other_tenants` assumed
  every collection answers `{items: [...]}` while `GET /v1/me/data-requests` and
  `GET /v1/admin/data-requests/retention-exceptions` answer a bare JSON array.

`apps/console/app/tokens.css` is regenerated by the console build from `design/tokens.json`;
the committed copy had drifted, so it changes here as a by-product of running `npm run check`.

## Settings

App (`.env` / Terraform): `MANDI_PROVIDER` (`data_gov_in` | `fake` | `off`, default `off`),
`MANDI_BASE_URL`, `MANDI_API_KEY`, `MANDI_TIMEOUT_S`, `MANDI_PAGE_SIZE`; `NLQ_LLM` (`claude` |
`fake` | `off`, default `off`), `NLQ_LLM_MODEL` (`claude-opus-5`), `NLQ_LLM_MAX_TOKENS`,
`NLQ_ROW_LIMIT` (200), `NLQ_STATEMENT_TIMEOUT_MS` (5000). The prd guard refuses
`MANDI_PROVIDER=fake`, `NLQ_LLM=fake`, and `data_gov_in` without a key. All rows are in
`docs/deploy/configuration.md`.

Tenant: `settings.mandi` = `{enabled, commodities: {crop_code: [published names]},
lookback_days}`; `settings.referral` = `{enabled, referrer_reward_paise, store_reward_paise,
reward_note, claim_window_days}`.

## Human gates

* **data.gov.in account, key and licence.** Register at data.gov.in, accept the Government
  Open Data Licence — India, put the key in Secret Manager as `MANDI_API_KEY` and set
  `MANDI_PROVIDER=data_gov_in`. Until then FM-012 is wired end to end but holds no data.
* **The commodity mapping.** `tenant.settings.mandi.commodities` must be checked against the
  live feed per pilot crop ("Paddy(Dhan)(Common)" and friends); the English-name fallback is
  right for some crops and wrong for others.
* **The referral reward values.** `referrer_reward_paise` and `store_reward_paise` are 0
  placeholders. The real numbers, and how the credit is actually given (khata credit, a free
  input, a voucher), are a commercial decision to record per tenant before the pilot. The
  `rewarded` step is a manual confirmation today; automating the credit is a follow-up.
* **`ANTHROPIC_API_KEY`** for AN-016 in stg / prd, then `NLQ_LLM=claude`. The same key as
  DX-004 / VA-004; the data-processing review is extended by one path that carries a schema
  and a business question and no row.
* **Android App Links** for `https://kisan.farmerapp.in/r/<code>`: the manifest intent filter
  and the `assetlinks.json` on the domain, so an invite link opens the app.
  `MarketRepository.rememberCode()` is ready for it; sharing and claiming already work.
* **Translations**: the te / hi / kn / mr strings for both features are machine-assisted and
  need native-speaker review (NF-008), like every bundle so far.
* **Infra follow-ups** (not in this branch): Cloud Scheduler for `mandi-prices`, the
  `MANDI_*` / `NLQ_*` variables in `infra/envs/*`, and the `farmerapp_readonly` role on Cloud
  SQL (the migration creates it; the grant to the runtime IAM user is a Terraform change).

## Follow-ups

* **The agent app's registration wizard** does not yet have a referral-code field. The API
  accepts and attributes `referral_code` on `POST /v1/farmers` and that path is tested end to
  end; the A21 draft (`packages/core/lib/src/farmers/registration_draft.dart`) and the
  officer-app basics step are the remaining piece, and are outside this branch's scope.
* **AN-016 over BigQuery** once the console moves there (SPEC 5.3 P1): `views.py` becomes a
  mapping onto `farmerapp_views.v_*` and `dim_viewer_scope` replaces the GUCs.
* **Referral rewards as khata credit** once the reward values exist.

## Tests

* `tests/market/` — the adapter (what leaves, rupees → paise, junk tolerated), the refresh
  (idempotent, per-district × grown crop, failures counted), the reads (latest date only,
  nearest market first) and both routes including the date and source assertions.
* `tests/referrals/` — codes, the full attribution path through **both** registration routes,
  self-referral, double attribution (including a different referrer), the claim window, the
  tenant switch, pending-invite reuse, the reward step, the per-store console view, store
  manager scoping and cross-tenant isolation.
* `tests/nlq/test_sql_guard.py` — 12 accepted business queries and **41 injection attempts**
  (writes, stacked statements, CTE writes, tables, `pg_catalog`, `information_schema`,
  `COPY`, `COPY … TO PROGRAM`, `pg_read_file`, `dblink`, `pg_sleep`, `current_setting`,
  `set_config`, `::regclass`, `SELECT … INTO`, `FOR UPDATE`), all rejected with a reason.
* `tests/nlq/test_ask.py` — the spec's acceptance question end to end; a cluster head seeing
  only their own cluster while the SQL has no cluster filter; the `llm_call_log` record
  (question, SQL, validation, row count); the read-only role refused on every base table;
  the savepoint rollback; refusals; the PII guard on the question; cross-tenant isolation.
* `tests/authz/test_matrix.py` — fixtures for the six new operations, so every role is
  asserted against every new route.
* Console: `npm run check` green; `e2e/m8.spec.ts` (4 specs) covers the Ask panel (answer +
  rows + "SQL used", a friendly refusal, the PII refusal) and C95 referrals.
* Mobile: `apps/farmer/test/mandi_prices_test.dart` and `referral_test.dart` (22 tests) cover
  the models, the cache with its "as of", offline behaviour, both screens, the entry points
  from F40 and F70, sharing, and the pending-code claim path.
