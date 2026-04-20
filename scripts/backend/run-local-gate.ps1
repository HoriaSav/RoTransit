param(
    [string]$BackendBaseUrl = "http://localhost:8085",
    [string]$OtpBaseUrl = "http://localhost:8080/otp",
    [switch]$SkipBackendTests
)

$ErrorActionPreference = "Stop"
$prePushScript = Join-Path $PSScriptRoot "pre-push-check.ps1"

if (-not (Test-Path $prePushScript)) {
    throw "Missing script: $prePushScript"
}

Write-Host "Running RoTransit local reliability gate..."
if ($SkipBackendTests) {
    & $prePushScript -BaseUrl $BackendBaseUrl -OtpBaseUrl $OtpBaseUrl -SkipBackendTests
} else {
    & $prePushScript -BaseUrl $BackendBaseUrl -OtpBaseUrl $OtpBaseUrl
}
exit $LASTEXITCODE
