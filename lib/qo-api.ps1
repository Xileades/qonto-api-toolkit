# qo-api.ps1 - minimal client for the Qonto Business API (thirdparty.qonto.com/v2), API-key auth
# Read-only by construction: no helper issues POST/PATCH/DELETE.
# Windows PowerShell 5.1 compatible, no external dependency.

$script:QOBase   = 'https://thirdparty.qonto.com/v2'
$script:QOTokens = $null
$script:QOOrgs   = @{}
$script:QOLast   = [datetime]::MinValue

function QOTokensLoad {
    if ($script:QOTokens) { return $script:QOTokens }
    $p = Join-Path $env:USERPROFILE '.qonto\tokens.json'
    if (-not (Test-Path $p)) {
        throw "tokens.json not found ($p). See README.md"
    }
    $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $j.entites) { throw "tokens.json invalid: 'entites' property missing" }
    $script:QOTokens = $j.entites
    return $script:QOTokens
}

function QOEntites {
    # Companies declared in tokens.json (keys starting with _ are comments)
    (QOTokensLoad).PSObject.Properties.Name | Where-Object { $_ -notlike '_*' }
}

function QOEntite {
    param([Parameter(Mandatory)][string]$e)
    $t = QOTokensLoad
    if (-not ($t.PSObject.Properties.Name -contains $e)) {
        throw "Unknown company: '$e'. Known: $((QOEntites) -join ', ')"
    }
    $x = $t.$e
    if (-not $x.login -or -not $x.secret -or $x.secret -like 'PASTE*') {
        throw "Company '$e': login/secret not filled in tokens.json"
    }
    $x
}

function QOHdr {
    param([Parameter(Mandatory)][string]$e)
    $x = QOEntite $e
    # Qonto format: "login:secret" as-is. NO Bearer, NO Base64.
    @{ 'Authorization' = ('{0}:{1}' -f $x.login, $x.secret); 'Accept' = 'application/json' }
}

# Qonto limit: 1000 req / 10 s and 10,000 req / 10 min, per IP address.
# Deliberately slow: every machine behind the same public IP shares the budget.
function QOThrottle {
    param([int]$ms = 150)
    $d = (Get-Date) - $script:QOLast
    if ($d.TotalMilliseconds -lt $ms) {
        Start-Sleep -Milliseconds ([int]($ms - $d.TotalMilliseconds))
    }
    $script:QOLast = Get-Date
}

function QOQS {
    param([hashtable]$q)
    if (-not $q -or $q.Count -eq 0) { return '' }
    $parts = @()
    foreach ($k in $q.Keys) {
        $v = $q[$k]
        if ($null -eq $v -or $v -eq '') { continue }
        if ($v -is [array]) {
            # status[]=a&status[]=b : the key must end with []
            $kk = if ($k.EndsWith('[]')) { $k } else { $k + '[]' }
            foreach ($i in $v) {
                $parts += ('{0}={1}' -f [uri]::EscapeDataString($kk), [uri]::EscapeDataString([string]$i))
            }
        } else {
            $parts += ('{0}={1}' -f [uri]::EscapeDataString($k), [uri]::EscapeDataString([string]$v))
        }
    }
    if ($parts.Count -eq 0) { return '' }
    '?' + ($parts -join '&')
}

function QOGet {
    param(
        [Parameter(Mandatory)][string]$e,
        [Parameter(Mandatory)][string]$path,
        [hashtable]$query
    )
    $u = $script:QOBase + '/' + $path.TrimStart('/') + (QOQS $query)
    for ($try = 1; $try -le 5; $try++) {
        QOThrottle
        try { return Invoke-RestMethod -Uri $u -Headers (QOHdr $e) -Method Get }
        catch {
            $code = 0
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            # Only 429/500/503 are retried. 400/401/403/404/422: fix the request.
            if ($code -in 429,500,503 -and $try -lt 5) {
                Start-Sleep -Seconds ([math]::Pow(2, $try))
                continue
            }
            throw
        }
    }
}

# Qonto pagination: ?page=N&per_page=100 (max 100); the response carries
# meta.next_page (null on the last page) and meta.total_count.
function QOGetAll {
    param(
        [Parameter(Mandatory)][string]$e,
        [Parameter(Mandatory)][string]$path,
        [hashtable]$query,
        [int]$maxPages = 200
    )
    $out = @()
    $q = @{}
    if ($query) { foreach ($k in $query.Keys) { $q[$k] = $query[$k] } }
    if (-not $q.ContainsKey('per_page')) { $q['per_page'] = 100 }
    $q['page'] = 1
    $n = 0
    do {
        $r = QOGet $e $path $q
        $items = $null
        # The collection key is named after the resource (transactions, labels...).
        foreach ($p in $r.PSObject.Properties) {
            if ($p.Name -ne 'meta' -and ($p.Value -is [array] -or $p.Value -is [System.Collections.IList])) {
                $items = $p.Value; break
            }
        }
        if ($null -eq $items) {
            $c = @($r.PSObject.Properties | Where-Object { $_.Name -ne 'meta' })
            if ($c.Count -eq 1) { $items = @($c[0].Value) } else { $items = @($r) }
        }
        $out += $items
        $next = $null
        if ($r.meta -and $r.meta.PSObject.Properties.Name -contains 'next_page') { $next = $r.meta.next_page }
        if ($next) { $q['page'] = [int]$next }
        $n++
    } while ($next -and $n -lt $maxPages)
    return $out
}

# --- Organization and accounts -----------------------------------------------

function QOOrg {
    # Organization + bank accounts (with balances). Cached per company.
    param([Parameter(Mandatory)][string]$e, [switch]$externes, [switch]$force)
    if (-not $force -and -not $externes -and $script:QOOrgs.ContainsKey($e)) { return $script:QOOrgs[$e] }
    $q = @{}
    if ($externes) { $q['include_external_accounts'] = 'true' }
    $r = (QOGet $e 'organization' $q).organization
    if (-not $externes) { $script:QOOrgs[$e] = $r }
    $r
}

function QOMe {
    # Pre-flight: confirms which company answers for this key.
    param([Parameter(Mandatory)][string]$e)
    $o = QOOrg $e -force
    [pscustomobject]@{
        entite     = $e
        legal_name = $o.legal_name
        slug       = $o.slug
        siret      = $o.legal_number
        comptes    = @($o.bank_accounts).Count
    }
}

function QOComptes {
    # Bank accounts of one company, one object per account.
    param([Parameter(Mandatory)][string]$e, [switch]$externes)
    $o = QOOrg $e -externes:$externes -force:$externes
    foreach ($b in $o.bank_accounts) {
        [pscustomobject]@{
            entite     = $e
            nom        = $b.name
            slug       = $b.slug
            id         = $b.id
            iban       = $b.iban
            devise     = $b.currency
            solde      = [decimal]$b.balance
            disponible = [decimal]$b.authorized_balance
            statut     = $b.status
            principal  = [bool]$b.main
            externe    = [bool]$b.is_external_account
            maj        = $b.updated_at
        }
    }
}

function QOSoldes {
    # Group view: every account of every company (or of the ones passed).
    param([string[]]$entites)
    if (-not $entites) { $entites = QOEntites }
    $rows = foreach ($e in $entites) {
        try { QOComptes $e }
        catch { Write-Warning "$e : $($_.Exception.Message)" }
    }
    $rows | Sort-Object entite, nom
}

function QOCompteId {
    # Resolves an account by slug, id, iban or name (case-insensitive). Default: main account.
    param([Parameter(Mandatory)][string]$e, [string]$compte)
    $cs = @(QOComptes $e)
    if (-not $compte) {
        $m = $cs | Where-Object { $_.principal }
        if (-not $m) { $m = $cs[0] }
        return @($m)[0].id
    }
    $m = $cs | Where-Object { $_.slug -eq $compte -or $_.id -eq $compte -or $_.iban -eq $compte -or $_.nom -ieq $compte }
    if (-not $m) { throw "Account '$compte' not found for '$e'. Accounts: $(($cs | ForEach-Object { $_.slug }) -join ', ')" }
    @($m)[0].id
}

# --- Transactions ------------------------------------------------------------

function QOTransactions {
    # Transactions of one account. Dates as YYYY-MM-DD (filter on settled_at).
    # $statuts defaults to completed only (like the API). Pass pending,completed to see what is in flight.
    param(
        [Parameter(Mandatory)][string]$e,
        [string]$compte,
        [string]$du,
        [string]$au,
        [string[]]$statuts,
        [ValidateSet('', 'credit', 'debit')][string]$sens = '',
        [string[]]$includes,
        [hashtable]$extra
    )
    $q = @{ bank_account_id = (QOCompteId $e $compte); sort_by = 'settled_at:desc' }
    if ($du) { $q['settled_at_from'] = ([datetime]$du).ToString('yyyy-MM-ddT00:00:00Z') }
    if ($au) { $q['settled_at_to']   = ([datetime]$au).ToString('yyyy-MM-ddT23:59:59Z') }
    if ($statuts) { $q['status'] = $statuts }
    if ($sens) { $q['side'] = $sens }
    if ($includes) { $q['includes'] = $includes }
    if ($extra) { foreach ($k in $extra.Keys) { $q[$k] = $extra[$k] } }
    QOGetAll $e 'transactions' $q
}

function QOTransaction {
    param([Parameter(Mandatory)][string]$e, [Parameter(Mandatory)][string]$id)
    (QOGet $e "transactions/$id").transaction
}

function QOTx {
    # Flattens a Qonto transaction into a readable row (signed amount, local dates).
    param([Parameter(ValueFromPipeline)]$t)
    process {
        $signe = if ($t.side -eq 'debit') { -1 } else { 1 }
        [pscustomobject]@{
            date      = if ($t.settled_at) { ([datetime]$t.settled_at).ToLocalTime().ToString('yyyy-MM-dd') } else { $null }
            emis      = if ($t.emitted_at) { ([datetime]$t.emitted_at).ToLocalTime().ToString('yyyy-MM-dd') } else { $null }
            libelle   = $t.label
            montant   = $signe * [decimal]$t.amount
            devise    = $t.currency
            type      = $t.operation_type
            statut    = $t.status
            categorie = if ($t.cashflow_category) { $t.cashflow_category.name } else { $null }
            tva       = $t.vat_amount
            pieces    = @($t.attachment_ids).Count
            reference = $t.reference
            note      = $t.note
            id        = $t.id
        }
    }
}

# --- Attachments and statements ---------------------------------------------

function QOPiece {
    param([Parameter(Mandatory)][string]$e, [Parameter(Mandatory)][string]$id)
    (QOGet $e "attachments/$id").attachment
}

function QOTelechargerPiece {
    # Downloads an attachment (the URL is signed and short-lived: never store it).
    param([Parameter(Mandatory)][string]$e, [Parameter(Mandatory)][string]$id, [Parameter(Mandatory)][string]$dossier)
    $a = QOPiece $e $id
    New-Item -ItemType Directory -Path $dossier -Force | Out-Null
    $f = Join-Path $dossier ($a.file_name -replace '[\\/:*?"<>|]', '_')
    QOThrottle
    Invoke-WebRequest -Uri $a.url -OutFile $f
    $f
}

function QOReleves {
    # Available bank statements (PDF).
    param([Parameter(Mandatory)][string]$e, [hashtable]$query)
    QOGetAll $e 'statements' $query
}

# --- Other reads ------------------------------------------------------------

function QOEtiquettes       { param([Parameter(Mandatory)][string]$e) QOGetAll $e 'labels' }
function QOMembres          { param([Parameter(Mandatory)][string]$e) QOGetAll $e 'memberships' }
function QOBeneficiaires    { param([Parameter(Mandatory)][string]$e) QOGetAll $e 'beneficiaries' }
function QOCartes           { param([Parameter(Mandatory)][string]$e) QOGetAll $e 'cards' }
function QOFacturesFourn    { param([Parameter(Mandatory)][string]$e, [hashtable]$query) QOGetAll $e 'supplier_invoices' $query }
function QOFacturesClients  { param([Parameter(Mandatory)][string]$e, [hashtable]$query) QOGetAll $e 'client_invoices' $query }
function QOVirements        { param([Parameter(Mandatory)][string]$e, [hashtable]$query) QOGetAll $e 'transfers' $query }
