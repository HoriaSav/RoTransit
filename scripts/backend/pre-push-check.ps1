param(
    [string]$BaseUrl = "http://localhost:8085",
    [string]$OtpBaseUrl = "http://localhost:8080/otp",
    [switch]$SkipBackendTests
)

$ErrorActionPreference = "Stop"

Write-Host "1) Running stack reliability checks..."
$stackScript = Join-Path $PSScriptRoot "stack-health-check.ps1"
if (-not (Test-Path $stackScript)) {
    throw "Missing script: $stackScript"
}
if ($SkipBackendTests) {
    & $stackScript -BackendBaseUrl $BaseUrl -OtpBaseUrl $OtpBaseUrl
} else {
    & $stackScript -BackendBaseUrl $BaseUrl -OtpBaseUrl $OtpBaseUrl -RunBackendTests
}
if ($LASTEXITCODE -ne 0) {
    throw "Stack reliability checks failed."
}
Write-Host "Stack reliability checks passed."

Write-Host "2) Checking staged files for forbidden artifacts..."
$staged = git diff --cached --name-only
if ($staged) {
    $bad = $staged | Select-String -Pattern '^backend/target/'
    if ($bad) {
        throw "Staged files include backend/target artifacts. Unstage them before push."
    }
}
Write-Host "No forbidden staged artifacts."

Write-Host "Pre-push check completed successfully."
