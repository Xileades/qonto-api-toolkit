# test-credentials.ps1 - offline tests of the credential loading in lib/qo-api.ps1.
# No network, no Windows API, no real secret: every value below is fictitious.
# Run:  pwsh -NoProfile -File tests/test-credentials.ps1      (exit code 1 on failure)
$ErrorActionPreference = 'Stop'
$lib  = Join-Path $PSScriptRoot '..\lib\qo-api.ps1'
$tmp  = Join-Path ([IO.Path]::GetTempPath()) ('qo-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$script:fail = 0

function Check($name, [scriptblock]$test) {
    try { $r = & $test } catch { $r = "exception: $($_.Exception.Message)" }
    if ($r -eq $true) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name -> $r"; $script:fail++ }
}
function Throws($sb) { try { & $sb | Out-Null; return $null } catch { return $_.Exception.Message } }
. $lib                               # dot-sourced once, at script level
function Fresh($homeDir) {          # new session state, same functions
    $env:QONTO_HOME = $homeDir
    $script:QOTokens = $null; $script:QOCFG = $null; $script:QOKVJ = $null
}

# ---- File mode (no config.json) ----------------------------------------------
$fileHome = Join-Path $tmp 'file'; New-Item -ItemType Directory -Path $fileHome | Out-Null
@'
{ "entites": {
    "demo-a": { "label": "Demo A", "login": "demo-login-a", "secret": "demo-secret-a" },
    "demo-b": { "label": "Demo B", "login": "PASTE-LOGIN-HERE", "secret": "PASTE-SECRET-KEY-HERE" } } }
'@ | Set-Content -LiteralPath (Join-Path $fileHome 'tokens.json') -Encoding UTF8
Fresh $fileHome
Check 'file mode: entities listed'            { ((QOEntites) -join ',') -eq 'demo-a,demo-b' }
Check 'file mode: header is login:secret'     { (QOHdr 'demo-a').Authorization -eq 'demo-login-a:demo-secret-a' }
Check 'file mode: PASTE* placeholder rejected' { (Throws { QOEntite 'demo-b' }) -like "*no login/secret available*" }
Check 'file mode: unknown company rejected'   { (Throws { QOEntite 'nope' }) -like "Unknown company*Known: demo-a, demo-b" }
$emptyHome = Join-Path $tmp 'empty'; New-Item -ItemType Directory -Path $emptyHome | Out-Null
Fresh $emptyHome
Check 'file mode: missing tokens.json throws' { (Throws { QOTokensLoad }) -like 'tokens.json not found*' }

# ---- Key Vault mode (secret reader and user replaced by fakes) ---------------------
$kvHome = Join-Path $tmp 'kv'; New-Item -ItemType Directory -Path $kvHome | Out-Null
@'
{ "source": "keyvault",
  "keyvault": { "vaultUrl": "https://example-vault.vault.azure.net", "clientId": "00000000-0000-0000-0000-000000000000" },
  "entites": {
    "demo-a": { "label": "Demo A" },
    "demo-c": { "label": "Demo C", "api": false, "note": "no key" } } }
'@ | Set-Content -LiteralPath (Join-Path $kvHome 'config.json') -Encoding UTF8
Fresh $kvHome
$script:asked = @()
function QOVaultUser { 'janedoe' }
function QOVaultSecret { param([string]$name) $script:asked += $name; $script:fake[$name] }
$script:fake = @{ 'qonto-token-demo-a-janedoe' = "demo-login-a:demo-secret:with:colons`n" }

Check 'keyvault: entities listed from config, no vault read' { ((QOEntites) -join ',') -eq 'demo-a,demo-c' -and $script:asked.Count -eq 0 }
Check 'keyvault: default secret name used'    { $null = QOTokensLoad; $script:asked -contains 'qonto-token-demo-a-janedoe' }
Check 'keyvault: split at FIRST colon'        { $x = QOEntite 'demo-a'; $x.login -eq 'demo-login-a' -and $x.secret -eq 'demo-secret:with:colons' -and $x.label -eq 'Demo A' }
Check 'keyvault: header identical to file mode' { (QOHdr 'demo-a').Authorization -eq 'demo-login-a:demo-secret:with:colons' }
Check 'keyvault: api:false entity never read' { $script:asked.Count -eq 1 -and (Throws { QOEntite 'demo-c' }) -like '*no login/secret available*' }

Fresh $kvHome
$script:fake = @{ 'qonto-token-demo-a-janedoe' = 'NOSEPARATORVALUE-FICTITIOUS' }
Check 'keyvault: secret without colon -> clear error' {
    (Throws { QOTokensLoad }) -eq "Key Vault: secret 'qonto-token-demo-a-janedoe' has no ':' separator (expected login:secret-key)" }
Check 'keyvault: error never shows the value' { -not ((Throws { QOTokensLoad }) -like '*NOSEPARATOR*') }
Check 'keyvault: failure does not fall back to a file' {
    Set-Content -LiteralPath (Join-Path $kvHome 'tokens.json') -Value '{ "entites": { "demo-a": { "login": "x", "secret": "y" } } }'
    Fresh $kvHome; $script:fake = @{ 'qonto-token-demo-a-janedoe' = 'bad' }
    $m = Throws { QOEntite 'demo-a' }; $m -like "Key Vault:*" }
Fresh $kvHome
$script:fake = @{ 'qonto-token-demo-a-janedoe' = ':only-a-secret' }
Check 'keyvault: empty login -> clear error'  { (Throws { QOTokensLoad }) -like "Key Vault: secret '*' has an empty login or secret-key*" }

Remove-Item -Recurse -Force $tmp
Remove-Item Env:QONTO_HOME -ErrorAction SilentlyContinue
if ($script:fail) { Write-Host "$($script:fail) test(s) FAILED"; exit 1 }
Write-Host 'All tests passed'
