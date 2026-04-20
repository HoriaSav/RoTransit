param(
    [string]$BackendBaseUrl = "http://localhost:8085",
    [string]$OtpBaseUrl = "http://localhost:8080/otp",
    [switch]$RunBackendTests,
    [int]$MaxWaitSeconds = 120,
    [int]$RetryIntervalSeconds = 5
)

$ErrorActionPreference = "Stop"
$script:allPassed = $true
$script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$script:versionMatrixPath = Join-Path $PSScriptRoot "version-matrix.json"

function Write-Stage([string]$name) {
    Write-Host ""
    Write-Host "=== $name ===" -ForegroundColor Cyan
}

function Mark-Fail([string]$message) {
    Write-Host "[FAIL] $message" -ForegroundColor Red
    $script:allPassed = $false
}

function Mark-Pass([string]$message) {
    Write-Host "[PASS] $message" -ForegroundColor Green
}

function Try-GetJson([string]$url) {
    try {
        return Invoke-RestMethod -Uri $url -TimeoutSec 15
    } catch {
        return $null
    }
}

function Get-HttpStatus([string]$url) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 15
        return [int]$response.StatusCode
    } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            return [int]$_.Exception.Response.StatusCode.value__
        }
        return -1
    }
}

function Test-HttpOk([string]$url, [string]$name, [int[]]$acceptedStatuses = @(200)) {
    $status = Get-HttpStatus $url
    if ($acceptedStatuses -contains $status) {
        Mark-Pass "$name -> $status ($url)"
        return $true
    }
    Mark-Fail "$name -> $status ($url)"
    return $false
}

function Trim-EndSlash([string]$value) {
    if ($value.EndsWith("/")) { return $value.Substring(0, $value.Length - 1) }
    return $value
}

function Invoke-CommandSafe([string]$filePath, [string[]]$arguments) {
    & $filePath @arguments
    return $LASTEXITCODE
}

function Parse-SemVer([string]$value) {
    $m = [regex]::Match($value, '(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $m.Success) { return $null }
    return [PSCustomObject]@{
        Major = [int]$m.Groups[1].Value
        Minor = [int]$m.Groups[2].Value
        Patch = if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { 0 }
        Raw = $value
    }
}

function Test-MinVersion([string]$name, $actual, [int]$requiredMajor, [int]$requiredMinor) {
    if ($null -eq $actual) {
        Mark-Fail "$name version could not be parsed."
        return
    }
    if ($actual.Major -lt $requiredMajor -or ($actual.Major -eq $requiredMajor -and $actual.Minor -lt $requiredMinor)) {
        Mark-Fail "$name version $($actual.Raw) is below required $requiredMajor.$requiredMinor"
    } else {
        Mark-Pass "$name version $($actual.Raw) meets required $requiredMajor.$requiredMinor"
    }
}

function Get-VersionMatrix() {
    if (-not (Test-Path $script:versionMatrixPath)) {
        Mark-Fail "Missing version matrix file: $script:versionMatrixPath"
        return $null
    }
    return Get-Content $script:versionMatrixPath -Raw | ConvertFrom-Json
}

function Stage-VersionCheck($matrix) {
    Write-Stage "version-check"
    if ($null -eq $matrix) { return }

    $javaVersionRaw = cmd /c "java -version 2>&1" | Select-Object -First 1
    $javaParsed = Parse-SemVer $javaVersionRaw
    if ($null -eq $javaParsed) {
        Mark-Fail "Unable to parse Java version from: $javaVersionRaw"
    } elseif ($javaParsed.Major -ne [int]$matrix.java.requiredMajor) {
        Mark-Fail "Java major version is $($javaParsed.Major), expected $($matrix.java.requiredMajor)"
    } else {
        Mark-Pass "Java major version $($javaParsed.Major) matches expected"
    }

    $mvnVersionRaw = cmd /c "mvn -v 2>&1" | Select-Object -First 1
    $mvnParsed = Parse-SemVer $mvnVersionRaw
    Test-MinVersion "Maven" $mvnParsed ([int]$matrix.maven.requiredMajor) ([int]$matrix.maven.requiredMinor)

    $composeVersionRaw = cmd /c "docker compose version 2>&1" | Select-Object -First 1
    $composeParsed = Parse-SemVer $composeVersionRaw
    Test-MinVersion "Docker Compose" $composeParsed ([int]$matrix.dockerCompose.requiredMajor) ([int]$matrix.dockerCompose.requiredMinor)

    $composeFile = Join-Path $script:repoRoot "docker-compose.yml"
    if (Test-Path $composeFile) {
        $composeText = Get-Content $composeFile -Raw
        $postgresMatch = [regex]::Match($composeText, 'image:\s*postgres:(\d+)')
        if ($postgresMatch.Success) {
            $actualMajor = [int]$postgresMatch.Groups[1].Value
            $expectedMajor = [int]$matrix.postgres.requiredImageMajor
            if ($actualMajor -eq $expectedMajor) {
                Mark-Pass "Postgres image major $actualMajor matches expected"
            } else {
                Mark-Fail "Postgres image major is $actualMajor, expected $expectedMajor"
            }
        } else {
            Mark-Fail "Could not detect postgres image major in docker-compose.yml"
        }
    }
}

function Stage-ServiceReadiness() {
    Write-Stage "service-readiness"
    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        $ps = (docker compose ps --format json) 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $ps) {
            Start-Sleep -Seconds $RetryIntervalSeconds
            continue
        }
        $services = $ps | ConvertFrom-Json
        if ($services -and $services.Count -ge 3) {
            $db = $services | Where-Object { $_.Service -eq "db" }
            $otp = $services | Where-Object { $_.Service -eq "otp" }
            $app = $services | Where-Object { $_.Service -eq "app" }
            if ($db.State -eq "running" -and $otp.State -eq "running" -and $app.State -eq "running") {
                $ready = $true
                break
            }
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }

    if (-not $ready) {
        Mark-Fail "Services are not all running (db/otp/app) within timeout ${MaxWaitSeconds}s."
        Write-Host "Recent service state:"
        docker compose ps
        Write-Host ""
        Write-Host "Recent otp logs:"
        docker compose logs otp --tail=80
        return
    }
    Mark-Pass "docker compose services db/otp/app are running"
}

function Stage-OtpApiDiscovery($matrix) {
    Write-Stage "otp-api-discovery"
    $base = Trim-EndSlash $OtpBaseUrl
    $alt = if ($base.EndsWith("/otp")) { $base.Substring(0, $base.Length - 4) } else { "$base/otp" }
    $probeUrls = @(
        "$base",
        "$alt",
        "$base/gtfs/v1",
        "$alt/gtfs/v1",
        "$base/routers/default",
        "$alt/routers/default"
    ) | Select-Object -Unique
    $shapeDetected = $false
    foreach ($url in $probeUrls) {
        $status = Get-HttpStatus $url
        if (@(200, 400, 401, 403, 405) -contains $status) {
            Mark-Pass "OTP API reachable at $url (status $status)"
            $shapeDetected = $true
            break
        }
    }
    if (-not $shapeDetected) {
        Mark-Fail "Could not detect reachable OTP API shape from base '$OtpBaseUrl'"
    }

    $versionPayload = Try-GetJson $base
    if ($null -eq $versionPayload) {
        $versionPayload = Try-GetJson $alt
    }
    if ($versionPayload -and $versionPayload.version -and $versionPayload.version.version) {
        $actualOtpVersion = [string]$versionPayload.version.version
        $expectedPrefix = [string]$matrix.otp.expectedVersionPrefix
        if ($expectedPrefix -and -not $actualOtpVersion.StartsWith($expectedPrefix)) {
            Mark-Fail "OTP version '$actualOtpVersion' does not match expected prefix '$expectedPrefix'"
        } else {
            Mark-Pass "OTP version '$actualOtpVersion' matches expected policy"
        }
    } else {
        Mark-Fail "Unable to read OTP version payload from '$base' or '$alt'"
    }
}

function Stage-BackendE2ESmoke() {
    Write-Stage "backend-e2e-smoke"
    $healthOk = Test-HttpOk "$BackendBaseUrl/api/health" "Backend health"
    $citiesOk = Test-HttpOk "$BackendBaseUrl/api/cities" "Cities endpoint"
    if (-not $healthOk -or -not $citiesOk) { return }

    $cities = Try-GetJson "$BackendBaseUrl/api/cities"
    if ($null -eq $cities -or $cities.Count -eq 0) {
        Mark-Fail "/api/cities returned empty payload"
        return
    }

    $city = $cities[0]
    $cityId = $city.id
    Mark-Pass "Using city '$($city.name)' ($cityId) for probes"

    $serviceDate = (Get-Date).ToString("yyyy-MM-dd")
    $serviceTime = (Get-Date).ToString("HH:mm:ss")
    $routeSearchUrl = "$BackendBaseUrl/api/routes/search?cityId=$cityId&origin=45.650,25.610&destination=45.640,25.600&serviceDate=$serviceDate&serviceTime=$serviceTime&passengerCount=1&offset=0&limit=3"
    $nearbyUrl = "$BackendBaseUrl/api/stops/nearby?cityId=$cityId&lat=45.645&lon=25.589&radiusMeters=500"

    [void](Test-HttpOk $routeSearchUrl "Route search")
    [void](Test-HttpOk $nearbyUrl "Nearby stops")
}

function Stage-DbConsistency() {
    Write-Stage "db-consistency"
    $sql = "select name, otp_base_url from cities order by name;"
    $output = (docker compose exec -T db psql -U admin -d rotransit -At -F '|' -c $sql) 2>$null
    if ($LASTEXITCODE -ne 0) {
        Mark-Fail "Failed querying cities table via docker compose exec db psql"
        return
    }
    if (-not $output) {
        Mark-Fail "Cities table query returned no rows"
        return
    }
    $rows = @($output -split "`n" | Where-Object { $_ -and $_.Contains("|") })
    if ($rows.Count -eq 0) {
        Mark-Fail "Cities table appears empty"
        return
    }
    Mark-Pass "Cities seed exists ($($rows.Count) row(s))"

    foreach ($row in $rows) {
        $parts = $row -split '\|', 2
        $cityName = $parts[0]
        $otpUrl = $parts[1]
        if (-not ($otpUrl.StartsWith("http://") -or $otpUrl.StartsWith("https://"))) {
            Mark-Fail "City '$cityName' has invalid otp_base_url '$otpUrl'"
        }
    }
}

function Stage-BackendTests() {
    if (-not $RunBackendTests) { return }
    Write-Stage "backend-tests"
    $backendDir = Join-Path $script:repoRoot "backend"
    $mvnwCmd = Join-Path $backendDir "mvnw.cmd"
    Push-Location $backendDir
    try {
        if (Test-Path $mvnwCmd) {
            $exitCode = Invoke-CommandSafe $mvnwCmd @("test", "-q")
            if ($exitCode -eq 0) {
                Mark-Pass "Backend tests passed (mvnw.cmd)"
            } else {
                Mark-Fail "Backend tests failed via mvnw.cmd"
            }
        } else {
            mvn test -q
            if ($LASTEXITCODE -eq 0) {
                Mark-Pass "Backend tests passed (mvn)"
            } else {
                Mark-Fail "Backend tests failed via mvn"
            }
        }
    } finally {
        Pop-Location
    }
}

Write-Host "RoTransit stack check starting..."
$matrix = Get-VersionMatrix
Stage-VersionCheck $matrix
Stage-ServiceReadiness
Stage-OtpApiDiscovery $matrix
Stage-BackendE2ESmoke
Stage-DbConsistency
Stage-BackendTests

Write-Host ""
if ($script:allPassed) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    exit 0
}
Write-Host "ONE OR MORE CHECKS FAILED" -ForegroundColor Red
exit 1
