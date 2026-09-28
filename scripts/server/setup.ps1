param(
    [switch]$SkipTunnelTokenCheck
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

function Ensure-EnvFile {
    param(
        [string]$ExamplePath,
        [string]$TargetPath,
        [string]$Label
    )

    if (Test-Path $TargetPath) {
        Write-Host ('[ok] ' + $Label + ' exists: ' + $TargetPath)
        return
    }

    if (-not (Test-Path $ExamplePath)) {
        throw "Missing example file: $ExamplePath"
    }

    Copy-Item $ExamplePath $TargetPath
    Write-Host ('[created] ' + $Label + ' from example: ' + $TargetPath)
}

function Test-TunnelToken {
    param([string]$EnvPath)

    $content = Get-Content $EnvPath -Raw
    if ($content -match 'TUNNEL_TOKEN\s*=\s*(.+)' ) {
        $token = $Matches[1].Trim().Trim('"').Trim("'")
        if ($token -and $token -ne "eyJ..." -and $token.Length -gt 20) {
            Write-Host '[ok] Cloudflare tunnel token is set'
            return $true
        }
    }

    Write-Host '[action] Edit cloudflare/.env and set TUNNEL_TOKEN from Zero Trust -> Tunnels -> rotransit-home'
    return $false
}

Push-Location $repoRoot
try {
    Write-Host "RoTransit server setup (repo root: $repoRoot)"

    Ensure-EnvFile `
        -ExamplePath (Join-Path $repoRoot "db\postgres\.env.example") `
        -TargetPath (Join-Path $repoRoot "db\postgres\.env") `
        -Label "Postgres env"

    Ensure-EnvFile `
        -ExamplePath (Join-Path $repoRoot "cloudflare\.env.example") `
        -TargetPath (Join-Path $repoRoot "cloudflare\.env") `
        -Label "Cloudflare env"

    $gtfsZip = Join-Path $repoRoot "otp\gtfs\ro-ratbv.zip"
    if (-not (Test-Path $gtfsZip)) {
        throw "Missing GTFS feed: otp/gtfs/ro-ratbv.zip (see README.md, Run it)"
    }
    Write-Host '[ok] GTFS feed present: otp/gtfs/ro-ratbv.zip'

    $osmDir = Join-Path $repoRoot "otp\osm"
    if (-not (Test-Path $osmDir) -or -not (Get-ChildItem $osmDir -Filter *.pbf -ErrorAction SilentlyContinue)) {
        Write-Host '[warn] No OSM .pbf found under otp/osm/ - OTP graph build may fail until you add one (see README.md, Run it)'
    } else {
        Write-Host '[ok] OSM extract present under otp/osm/'
    }

    docker compose version | Out-Null
    Write-Host '[ok] Docker Compose is available'

    if (-not $SkipTunnelTokenCheck) {
        $cloudflareEnv = Join-Path $repoRoot "cloudflare\.env"
        if (-not (Test-TunnelToken -EnvPath $cloudflareEnv)) {
            exit 1
        }
    }

    Write-Host ""
    Write-Host "Setup complete. Start the stack with:"
    Write-Host "  .\scripts\server\up.ps1"
    Write-Host ""
    Write-Host "Public API (after cloudflared is running): https://api.horiasavin.me"
    Write-Host "Flutter: flutter run --dart-define=API_BASE_URL=https://api.horiasavin.me"
}
finally {
    Pop-Location
}
