# Pitfalls

What the Qonto Business API documentation does not say, or says in a place you
will not read first. Verified against the live API in September 2026.

## The auth header is `login:secret` - no `Bearer`, no Base64

API-key authentication is `Authorization: <login>:<secret>`, a raw
concatenation with a colon. It looks like HTTP Basic but is **not** Base64
encoded, and it is **not** `Bearer <secret>` (that form is for OAuth access
tokens, documented on the same pages). Get it wrong and you get a 401 - and
enough 401s throttle your whole IP (see below).

Both values are shown on the *API key* page of the web app, **per
organization**. Switch organization first if you have several.

## Pending transactions are hidden by default

`GET /v2/transactions` filters on `status[]` and the default is
**`completed` only**. Card payments still authorising, transfers in flight,
direct debits announced but not settled: invisible unless you ask for
`status[]=pending&status[]=completed`. The symptom is a "balance that does not
add up" - the balance already accounts for them, your listing does not.

`QOTransactions -statuts pending,completed` is the fix.

## `amount` is always positive

The direction is in `side` (`credit` / `debit`). Summing `amount` without
looking at `side` produces a nonsense figure. `QOTx` signs the amount for you.

## Timestamps are UTC

`settled_at`, `emitted_at`, `created_at`, `updated_at` are ISO 8601 in UTC. A
card payment settled at 23:30 UTC on the 31st belongs to the 1st in Paris.
Convert before grouping by day or month; `QOTx` converts to local time.

## One account per call

`/v2/transactions` requires `bank_account_id` (or `iban`). An organization with
several accounts needs one call per account; `QOComptes` lists them. Connected
external (non-Qonto) accounts only appear on `/v2/organization` with
`include_external_accounts=true` (`QOComptes -externes`).

## Two balances

`balance` is the booked balance; `authorized_balance` is what is actually
available after pending card authorisations. Say which one you are quoting.

## Array query parameters need `[]`

`status[]=pending&status[]=completed`, `includes[]=labels`,
`operation_type[]=card`. Without the brackets the parameter is ignored or
rejected. `QOQS` appends `[]` to any array value automatically.

## Rate limits are per IP, and 401s count

**1,000 requests / 10 s and 10,000 / 10 min, per IP address** - not per key,
not per organization. Several machines behind one office NAT share the budget.
Exceeding it returns 429.

Separately, **more than 200 responses with status 401 within one hour** throttle
the IP. A misconfigured key inside a retry loop can therefore lock out every
colleague on the same network. Never retry a 401.

## Pagination stops silently

`per_page` defaults to and caps at **100**. The response carries
`meta.next_page` (null on the last page) and `meta.total_count`. Reading only
the first page of a busy account gives you the last 100 operations and no
error. `QOGetAll` loops until `next_page` is null.

## Attachment URLs expire

`GET /v2/attachments/{id}` returns a signed `url`. It is short-lived: download
immediately, never persist the URL, never paste it in a document.

## `category` is deprecated

Use `cashflow_category` / `cashflow_subcategory` (objects with `id` and
`name`). The old `category` string is still present but no longer maintained.

## 404 may mean "other organization"

An id that exists in company A queried with company B's key returns 404, not
403. Check which key you used before concluding the resource does not exist.

## Error bodies are JSON:API

```json
{ "errors": [ { "code": "...", "detail": "...", "source": { "parameter": "..." } } ], "trace_id": "..." }
```

`trace_id` matches the `X-Tyk-Trace-Id` response header and is what Qonto
support asks for.

## Sandbox needs an extra header

`https://thirdparty-sandbox.staging.qonto.co/v2` requires
`X-Qonto-Staging-Token` on every request, with that exact capitalisation.
This toolkit targets production only.
