# Qonto API Toolkit

A minimal PowerShell client for the **Qonto Business API**, plus a Claude skill
and a catalogue of the pitfalls that cost time. Built for people who run
**several companies on Qonto** and want one place to see balances, transactions,
statements and attachments across all of them.

Written for Windows PowerShell 5.1 (the one already on the machine), works on
PowerShell 7. No external dependency. **Read-only by construction**: nothing in
here can move money.

## Why this exists

Qonto's own integrations (including the Claude connector) bind to **one
organization**. A group with four companies needs four connections and still
gets no consolidated view. The Qonto Business API lets any customer generate an
API key per organization; this toolkit takes one key per company and gives you
`QOSoldes` - every account of every company in one table - and the same
per-company access to transactions, statements and attachments.

Along the way a few behaviours turned out to be non-obvious (the auth header is
`login:secret` with no `Bearer`, the transactions endpoint silently hides
pending operations, rate limits are per **IP address**, not per key). They are
documented in `docs/PITFALLS.md` so they cost you nothing.

## What is in here

| Path | Contents |
|---|---|
| `lib/qo-api.ps1` | the client: auth, pagination, throttling, bounded retry, group view |
| `config/tokens.example.json` | credentials file template, one entry per company |
| `config/config.example.json` | optional: read credentials from Azure Key Vault instead |
| `tests/test-credentials.ps1` | offline tests of credential loading (no network, fictitious values) |
| `docs/PITFALLS.md` | what the documentation does not say |
| `skills/qonto-access/` | Claude skill wrapping the library |
| `examples/` | ready-to-run scripts: group balances, monthly CSV export, consolidated cashflow |

## Requirements

- Windows PowerShell 5.1 or PowerShell 7
- A Qonto API key for each organization you want to read

## Quick start

### 1. Create a key per organization

In the Qonto web app, **switch to the organization**, then *Integrations and
partnerships* → *API key*. Note the two values shown: the **login**
(organization identifier) and the **secret key**. Repeat for every company.

### 2. Place the credentials file

```powershell
New-Item -ItemType Directory -Path "$env:USERPROFILE\.qonto" -Force
Copy-Item .\config\tokens.example.json "$env:USERPROFILE\.qonto\tokens.json"
notepad "$env:USERPROFILE\.qonto\tokens.json"
```

It is JSON: replace the text **inside** the quotes, not the quotes themselves.
Rename the entries (`my-company`, `other-company`) to whatever short names you
want to type; delete the ones you do not need.

This file never belongs on a network share or in a repository. One key per
person: individual traceability and revocation.

### Optional: credentials in Azure Key Vault instead of a file

If your people sign in to Windows with Entra ID (Microsoft 365), the Qonto
credentials can stay in an Azure Key Vault and be read **at run time, in
memory**, with the user's own Windows sign-in - no password prompt, no secret on
disk, nothing to copy when someone gets a new PC. Put a `config.json` (it holds
**no** secret) next to where `tokens.json` would be:

```powershell
Copy-Item .\config\config.example.json "$env:USERPROFILE\.qonto\config.json"
notepad "$env:USERPROFILE\.qonto\config.json"   # vault URL, app id, companies
```

One secret per company **and per person**, named by default
`qonto-token-{company}-{user}` (`{user}` = the part of the sign-in before `@`,
letters and digits only: `jane.doe@contoso.com` -> `janedoe`). Its value is the
Qonto **login and secret key joined by a colon**, `login:secret-key`; the library
splits it at the first colon. Grant each person **Key Vault Secrets User on their
own secrets only**, so per-person traceability and revocation are kept. One-time
setup: an Entra app registration (public client, no secret) with the delegated
permission *Azure Key Vault / user_impersonation*, admin consent, and the
redirect URI `ms-appx-web://microsoft.aad.brokerplugin/<app id>`. Because
`config.json` is not secret, it can be pushed to every workstation by Intune.

Without `config.json`, nothing changes: the library reads `tokens.json` as
before. If the vault cannot be read, the library stops with a `Key Vault:` error
and does **not** fall back to a file. The one trap of this mode is in
[`docs/PITFALLS.md`](docs/PITFALLS.md) ("Key Vault mode"). Set `QONTO_HOME` to
use another folder than `%USERPROFILE%\.qonto`.

### 3. Load and check

```powershell
. .\lib\qo-api.ps1
QOEntites                    # declared companies
QOMe 'my-company'            # legal_name: is it the company you expect?
QOSoldes | Format-Table      # every account of every company, with balances
```

## Usage

```powershell
# Group balances
QOSoldes | Format-Table entite, nom, solde, disponible, devise

# Accounts of one company (add -externes to include connected external accounts)
QOComptes 'my-company'

# Debits of August 2026 on the main account, flattened into readable rows
QOTransactions 'my-company' -du 2026-08-01 -au 2026-08-31 -sens debit | QOTx | Format-Table

# Include pending operations (hidden by default - see PITFALLS)
QOTransactions 'my-company' -du 2026-08-01 -statuts pending,completed | QOTx

# A specific account, by slug, id, IBAN or display name
QOTransactions 'my-company' -compte 'my-company-bank-account-2' -du 2026-01-01

# One transaction, its attachments, download one
$t = QOTransaction 'my-company' $id
QOTelechargerPiece 'my-company' $t.attachment_ids[0] "$env:USERPROFILE\Downloads\qonto"

# Statements, labels, cards, beneficiaries, invoices
QOReleves 'my-company'
QOEtiquettes 'my-company'
QOFacturesFourn 'my-company'

# Any other GET endpoint, paginated
QOGetAll 'my-company' 'memberships'
QOGet 'my-company' 'memberships/me'
```

## Functions

| Function | Role |
|---|---|
| `QOEntites` | companies declared in `tokens.json` (or `config.json` in Key Vault mode) |
| `QOMe $e` | pre-flight: legal name, slug, registration number behind the key |
| `QOOrg $e` | raw organization + accounts (cached per company) |
| `QOComptes $e [-externes]` | accounts of one company: name, slug, IBAN, balance, available |
| `QOSoldes [$companies]` | **group view**: every account of every company |
| `QOCompteId $e $account` | resolves slug / id / IBAN / name → account id (default: main account) |
| `QOTransactions $e [-compte] [-du] [-au] [-statuts] [-sens] [-includes] [-extra]` | transactions of one account, all pages |
| `QOTransaction $e $id` | one transaction |
| `… \| QOTx` | flattens: signed amount, local dates, cashflow category |
| `QOPiece $e $id` / `QOTelechargerPiece $e $id $dir` | attachment metadata / download |
| `QOReleves $e` | bank statements |
| `QOEtiquettes`, `QOMembres`, `QOBeneficiaires`, `QOCartes`, `QOFacturesFourn`, `QOFacturesClients`, `QOVirements` | other reads |
| `QOGet $e $path $query` / `QOGetAll` | raw / paginated GET on any endpoint |
| `QOThrottle` | rate-limit friendly pause |

Function and column names are French (`solde`, `disponible`, `libelle`…) because
the toolkit was written for a French group; the API fields underneath are
untouched, and `QOGet`/`QOGetAll` return raw API objects.

## The multi-company model

**One Qonto API key is bound to one organization.** There is no cross-company
key. `tokens.json` therefore holds one entry per company, and every call names
the company it targets. `QOSoldes` loops over all of them and reports - with a
warning, not silently - any company that fails.

A `404` may simply mean the resource belongs to a different organization.
Check the company before concluding it does not exist.

## Rate limits and safety

Qonto allows **1,000 requests / 10 s and 10,000 / 10 min, per IP address**.
Every machine behind the same public IP shares that budget. Exceeding it
returns HTTP 429. Separately, more than **200 responses with status 401 within
an hour** gets the IP throttled - a wrong key in a loop costs everyone behind
the same NAT their access, so stop at the first 401 and fix the credentials.

`QOThrottle` keeps ~6 requests/s. Only **429, 500 and 503** are retried, with
exponential back-off. `400`, `401`, `403`, `404`, `422` mean the request or the
key must be fixed, not repeated.

The client is read-only on purpose. If you extend it towards transfers or
payments, add a confirmation step and test on one case before any batch.

## How it compares

There are a dozen Qonto API clients on GitHub - Ruby, Go, PHP, JavaScript,
Kotlin, C#, a Python MCP server. All of them wrap **one organization** and stop
at the HTTP layer. This toolkit is different on three points:

- **multi-company by design** - one credentials file, one call for the whole
  group (`QOSoldes`, `examples/monthly-cashflow.ps1`);
- **zero install** - Windows PowerShell 5.1, already on every Windows machine;
- **the pitfalls are the product** - `docs/PITFALLS.md` and the Claude skill
  encode what the API does that its documentation does not say.

If you need a typed SDK in your language, use one of those. If you need to
answer "how much cash does the group have this morning" from a finance laptop,
use this.

## Contributing

Issues and pull requests welcome, particularly additions to `docs/PITFALLS.md`:
undocumented behaviours are the most valuable thing this repository can carry.

## Licence

MIT. See `LICENSE`.

Not affiliated with Qonto. Built by Xileades. API behaviours described here
were verified against the live API in September 2026 and may change.
