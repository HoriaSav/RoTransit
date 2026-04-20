param(
    [Parameter(Mandatory = $true)]
    [string]$CityId,
    [string]$GtfsPath = "otp/gtfs/ro-ratbv.zip",
    [string]$DbUrl = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GtfsPath)) {
    throw "GTFS zip was not found at path: $GtfsPath"
}

$cmd = @(
    "python",
    "scripts/db/import_gtfs_to_db.py",
    "--gtfs", $GtfsPath,
    "--city-id", $CityId
)

if ($DbUrl -ne "") {
    $cmd += @("--db-url", $DbUrl)
}

Write-Host "Running GTFS import..." -ForegroundColor Cyan
Write-Host ($cmd -join " ")
& $cmd[0] $cmd[1..($cmd.Length - 1)]
