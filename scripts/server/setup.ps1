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

    $backendEnv = Join-Path $repoRoot "backend_v2\.env"
    Ensure-EnvFile `
        -ExamplePath (Join-Path $repoRoot "backend_v2\.env.example") `
        -TargetPath $backendEnv `
        -Label "Backend env"

    foreach ($var in @('SPRING_DATASOURCE_PASSWORD', 'SPRING_SECURITY_PASSWORD')) {
        if (-not (Select-String -Path $backendEnv -Pattern "^$var=.+" -Quiet)) {
            throw "Set $var in backend_v2/.env (see backend_v2/README.md, Run locally)"
        }
    }
    Write-Host '[ok] backend_v2/.env has both passwords set'

    docker compose version | Out-Null
    Write-Host '[ok] Docker Compose is available'

    if (-not $SkipTunnelTokenCheck) {
        $cloudflareEnv = Join-Path $repoRoot "cloudflare\.env"
        if (-not (Test-TunnelToken -EnvPath $cloudflareEnv)) {
            exit 1
        }
    }

    Write-Host ""
    Write-Host "Setup complete. Start the stack (db, app on :8080, cloudflared) with:"
    Write-Host "  .\scripts\server\up.ps1"
    Write-Host ""
    Write-Host "In Cloudflare (Zero Trust -> Tunnels -> rotransit-home -> Public hostname) api.horiasavin.me must target http://app:8080,"
    Write-Host "and /admin/* should be blocked by a Cloudflare Access policy."
    Write-Host "Public API (after cloudflared is running): https://api.horiasavin.me/api/feeds"
    Write-Host "Flutter: flutter run --dart-define=API_BASE_URL=https://api.horiasavin.me"
}
finally {
    Pop-Location
}
