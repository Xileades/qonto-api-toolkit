# Changelog

## 1.1.0 — 2026-11-04

New, optional: Qonto credentials can be read from **Azure Key Vault** instead of `tokens.json`,
the same model as `pennylane-api-toolkit` 1.1.0. A `%USERPROFILE%\.qonto\config.json` with
`"source": "keyvault"` (see `config/config.example.json`) makes `QOTokensLoad` fetch one secret per
company and per person at run time, with an access token obtained silently from the Windows account
broker for the signed-in Entra ID user. The secret holds `login:secret-key` and is split at the first
colon. Nothing secret is written to disk, and a new workstation needs no copy of any key.
`config.json` holds no secret and can be deployed by Intune.

Without `config.json` nothing changes: `tokens.json` is read as before. `QOEntite`, `QOHdr` and the
skills behave the same in both modes, and the library stays read-only. In Key Vault mode a failure
throws a `Key Vault:` error and never falls back to a file. `QOEntites` lists the companies from
`config.json` without calling the vault. `$env:QONTO_HOME` overrides the `%USERPROFILE%\.qonto` folder.
New helpers: `QOHome`, `QOConfig`, `QOVaultToken`, `QOVaultUser`, `QOVaultSecret`, `QOSplitSecret`.
New pitfall (Key Vault mode): the broker returns `Success` with an empty token unless the v1
`resource` property is set, which PowerShell 5.1 only allows by reflection. New offline tests:
`tests/test-credentials.ps1`.

## 1.0.0 — 2026-09-22

First stable release. No functional change from 0.1.0: the skills, the PowerShell library and the
pitfall catalogue have been in daily production use, and the version now says so. Pinning this
toolkit at 1.0.0 is safe.

## 0.1.0

Initial public release.