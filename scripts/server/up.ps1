param(
    [switch]$Detached,
    [switch]$Build,
    [switch]$SkipSetup
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

Push-Location $repoRoot
try {
    if (-not $SkipSetup) {
        & (Join-Path $PSScriptRoot "setup.ps1")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    $args = @("compose", "up")
    if ($Detached) { $args += "-d" }
    if ($Build) { $args += "--build" }

    Write-Host "Starting RoTransit stack (db, backend_v2 app on :8080, cloudflared)..."
    & docker @args
}
finally {
    Pop-Location
}
