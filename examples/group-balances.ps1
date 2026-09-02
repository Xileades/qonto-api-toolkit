# Every account of every company, with balances and a grand total per currency.
#   .\examples\group-balances.ps1

. (Join-Path $PSScriptRoot '..\lib\qo-api.ps1')

$rows = QOSoldes
$rows | Format-Table entite, nom, solde, disponible, devise, statut -AutoSize

$rows | Group-Object devise | ForEach-Object {
    [pscustomobject]@{
        Currency  = $_.Name
        Booked    = ($_.Group | Measure-Object solde -Sum).Sum
        Available = ($_.Group | Measure-Object disponible -Sum).Sum
        Accounts  = $_.Count
    }
} | Format-Table -AutoSize
