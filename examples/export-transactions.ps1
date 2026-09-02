# Export one month of transactions (pending included) for every company to CSV.
#   .\examples\export-transactions.ps1 -Month 2026-08 -OutDir "$env:USERPROFILE\Desktop\qonto"

param(
    [Parameter(Mandatory)][string]$Month,          # YYYY-MM
    [string]$OutDir = (Join-Path $env:USERPROFILE 'Desktop\qonto')
)

. (Join-Path $PSScriptRoot '..\lib\qo-api.ps1')

$from = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', $null)
$to   = $from.AddMonths(1).AddDays(-1)
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

foreach ($e in QOEntites) {
    foreach ($acct in QOComptes $e) {
        $tx = QOTransactions $e -compte $acct.id -du $from.ToString('yyyy-MM-dd') -au $to.ToString('yyyy-MM-dd') -statuts pending,completed
        $file = Join-Path $OutDir ("{0}-{1}-{2}.csv" -f $e, $acct.slug, $Month)
        $tx | QOTx |
            Select-Object @{ n = 'entite'; e = { $e } }, @{ n = 'compte'; e = { $acct.nom } }, * |
            Export-Csv $file -NoTypeInformation -Encoding UTF8
        '{0,-24} {1,-36} {2,5} rows -> {3}' -f $e, $acct.nom, @($tx).Count, $file
    }
}
