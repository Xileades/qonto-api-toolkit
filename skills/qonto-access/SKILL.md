---
name: qonto-access
description: Access layer for the Qonto Business API across several companies - one key per organization, group balances, transactions, pagination, rate limits, pitfalls. Read-only. Load before any Qonto task, especially when more than one company is involved.
---

# Qonto - multi-company access layer

Any task hitting the Qonto API starts here. The native Qonto connector sees one
organization; this library sees all the ones declared in `tokens.json`.

## 1. Bootstrap

```powershell
. .\lib\qo-api.ps1
```

If the library is shared from a network drive, copy it locally first: the
`RemoteSigned` policy refuses an unsigned `.ps1` on a network path. Keep the
share as the source of truth and the local copy as a cache overwritten at every
run. Do **not** work around it by setting the policy to `Bypass`.

If `qo-api.ps1` throws "tokens.json not found", point the user at the README.
Never guess a key, never reuse someone else's, never print or log one.

## 2. Companies and keys

**One Qonto key is bound to one organization.** Hence one entry per company in
`%USERPROFILE%\.qonto\tokens.json`, never on a share, never in git. Each entry
has a `login` (organization identifier) and a `secret`, both shown in the web
app under *Integrations and partnerships → API key* after switching to that
organization.

Pre-flight before anything unusual:

```powershell
QOEntites            # available companies
QOMe 'my-company'    # legal_name: is it the company you expect?
```

## 3. Calling the API

Base `https://thirdparty.qonto.com/v2`, header `Authorization: <login>:<secret>`
- raw concatenation, **no `Bearer`, no Base64**. `QOHdr` builds it.

| Function | Role |
|---|---|
| `QOEntites` | companies in tokens.json |
| `QOMe $e` | pre-flight: which company answers |
| `QOComptes $e [-externes]` | accounts: name, slug, IBAN, balance, available |
| `QOSoldes [$companies]` | **group view**: every account of every company |
| `QOCompteId $e $account` | slug / id / IBAN / name → id (default: main account) |
| `QOTransactions $e [-compte] [-du] [-au] [-statuts] [-sens] [-includes]` | transactions, all pages |
| `QOTransaction $e $id` | one transaction |
| `… \| QOTx` | flattens: signed amount, local dates, category |
| `QOPiece` / `QOTelechargerPiece $e $id $dir` | attachment |
| `QOReleves $e` | statements |
| `QOEtiquettes`, `QOMembres`, `QOBeneficiaires`, `QOCartes`, `QOFacturesFourn`, `QOFacturesClients`, `QOVirements` | other reads |
| `QOGet $e $path $query` / `QOGetAll` | raw / paginated GET, any endpoint |
| `QOThrottle` | rate-limit friendly pause |

Responses wrap the object under the resource name (`{ organization: … }`,
`{ transactions: [...], meta: … }`). `QOGetAll` unwraps; `QOGet` does not.

## 4. The traps that make you say wrong things about cash

**a. `status` defaults to `completed`.** Without `-statuts pending,completed`,
in-flight operations are invisible and the total "does not match" the balance.
For any cash view, include `pending`.

**b. `amount` is always positive.** Direction is in `side`. `QOTx` signs it.

**c. Timestamps are UTC.** A 23:30 UTC settlement on the 31st is the 1st in
Paris. `QOTx` converts to local. `-du` / `-au` filter on `settled_at`.

**d. One account per call.** `/transactions` needs `bank_account_id`. A company
can have several accounts: `QOComptes` lists them; a per-company total adds
them up - including external accounts (`-externes`) if any are connected.

**e. Two balances.** `balance` = booked; `authorized_balance` = available after
pending card authorisations. Say which one you quote.

**f. 404 = missing OR other organization.** Check the key before concluding.

**g. `category` is deprecated.** Read `cashflow_category` / `cashflow_subcategory`.

**h. Attachment URLs are signed and expire.** Download at once, never store.

## 5. Pagination

`page` (from 1) + `per_page` (default and **max 100**). The response carries
`meta.next_page` (null on the last page) and `meta.total_count`. `QOGetAll`
handles it; if paginating by hand, loop until `next_page` is null - 100 rows
is rarely a full month.

## 6. Rate limits

**1,000 req / 10 s and 10,000 req / 10 min, per IP address** - shared by every
machine behind the same NAT. Exceeding → 429. More than **200 401s in an hour**
throttles the IP: a wrong key in a loop locks out colleagues, so stop at the
first 401 and fix tokens.json. `QOThrottle` keeps ~6 req/s.

## 7. Errors

JSON:API body: `{ errors: [ { code, detail, source: { pointer, parameter } } ], trace_id }`.
`trace_id` (= `X-Tyk-Trace-Id` header) is what Qonto support asks for.

| Code | Meaning | Reflex |
|---|---|---|
| 400 / 422 | invalid parameter | fix (often: `status[]` malformed, non-ISO date) |
| 401 | wrong login/secret or revoked key | **stop**, fix tokens.json (see §6) |
| 403 | insufficient rights on the organization | check the role of the member who created the key |
| 404 | missing **or other organization** | check the company |
| 429 | rate limit | wait, retry |

**Retry only 429, 500, 503.**

## 8. Endpoints (all GET, relative to `/v2`)

`organization` (+ `include_external_accounts=true`), `transactions`,
`transactions/{id}`, `transactions/{id}/attachments`, `attachments/{id}`,
`statements`, `labels`, `memberships`, `memberships/me`, `teams`,
`beneficiaries`, `transfers`, `bulk_transfers`, `recurring_transfers`, `cards`,
`supplier_invoices`, `client_invoices`, `clients`, `requests`.

Useful `transactions` filters: `status[]` (`pending`, `completed`, `declined`,
`reversed`), `side`, `operation_type[]` (`card`, `transfer`, `income`,
`direct_debit`, `cheque`, `swift_income`…), `settled_at_from/to`,
`emitted_at_from/to`, `updated_at_from/to` (ISO 8601), `with_attachments`,
`includes[]` (`vat_details`, `labels`, `attachments`), `sort_by`
(`settled_at:desc` by default).

Reference: https://docs.qonto.com

## 9. Discipline

This layer is **read-only**: no helper moves money, and none should be added
without an explicit decision by the user. Figures produced here feed cash
decisions: always state the company, the account, the period, whether
`pending` is included and which balance is quoted. When a company errors out in
`QOSoldes`, say so - a company missing from a group total is worse than no
total.

## Verification

```powershell
QOEntites                              # lists the declared companies
QOMe 'my-company'                      # expected legal_name
QOSoldes | Format-Table                # one row per account, no warning
(QOTransactions 'my-company' -du (Get-Date).AddDays(-30).ToString('yyyy-MM-dd')).Count   # > 0
```
