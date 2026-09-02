# Consolidated monthly cashflow across every company: inflows, outflows, net, per month.
#   .\examples\monthly-cashflow.ps1 -From 2026-01 -To 2026-08
#   .\examples\monthly-cashflow.ps1 -From 2026-01 -To 2026-08 -PerCompany

param(
    [Parameter(Mandatory)][string]$From,   # YYYY-MM
    [Parameter(Mandatory)][string]$To,     # YYYY-MM
    [switch]$PerCompany,
    [switch]$IncludePending
)

. (Join-Path $PSScriptRoot '..\lib\qo-api.ps1')

$start = [datetime]::ParseExact("$From-01", 'yyyy-MM-dd', $null)
$end   = [datetime]::ParseExact("$To-01",   'yyyy-MM-dd', $null).AddMonths(1).AddDays(-1)
$statuses = if ($IncludePending) { @('pending', 'completed') } else { @('completed') }

$rows = foreach ($e in QOEntites) {
    foreach ($acct in QOComptes $e) {
        QOTransactions $e -compte $acct.id -du $start.ToString('yyyy-MM-dd') -au $end.ToString('yyyy-MM-dd') -statuts $statuses |
            QOTx | Select-Object @{ n = 'entite'; e = { $e } }, @{ n = 'mois'; e = { $_.date.Substring(0, 7) } }, montant, devise
    }
}

$keys = if ($PerCompany) { 'entite', 'mois', 'devise' } else { 'mois', 'devise' }
$rows | Group-Object $keys | ForEach-Object {
    $g = $_.Group
    $o = [ordered]@{}
    if ($PerCompany) { $o.Company = $g[0].entite }
    $o.Month    = $g[0].mois
    $o.Currency = $g[0].devise
    $o.In       = ($g | Where-Object montant -gt 0 | Measure-Object montant -Sum).Sum
    $o.Out      = ($g | Where-Object montant -lt 0 | Measure-Object montant -Sum).Sum
    $o.Net      = ($g | Measure-Object montant -Sum).Sum
    $o.Count    = $g.Count
    [pscustomobject]$o
} | Sort-Object Month, Company | Format-Table -AutoSize
