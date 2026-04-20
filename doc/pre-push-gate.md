# Pre-push gate

Run this before every push:

1. Start required services (`db`, `otp`) and backend app.
2. Execute:

   `powershell -ExecutionPolicy Bypass -File scripts/backend/run-local-gate.ps1`

3. Push only if all checks pass.

## What this gate checks

- version policy from `scripts/backend/version-matrix.json`:
  - Java major
  - Maven minimum
  - Docker Compose minimum
  - PostgreSQL image major (from `docker-compose.yml`)
  - OTP runtime version prefix (from OTP logs)
- service readiness (`db`, `otp`, `app`) with timeout and retry
- OTP API shape probe
- backend smoke endpoints:
  - `/api/health`
  - `/api/cities`
  - `/api/routes/search` (city-aware)
  - `/api/stops/nearby` (city-aware)
- DB consistency smoke (`cities` seed + `otp_base_url` shape)
- backend tests (unless skipped)
- no `backend/target` artifacts are staged for commit

## Optional

Skip backend tests for faster local validation:

`powershell -ExecutionPolicy Bypass -File scripts/backend/run-local-gate.ps1 -SkipBackendTests`

If backend/OTP run on custom local URLs:

`powershell -ExecutionPolicy Bypass -File scripts/backend/run-local-gate.ps1 -BackendBaseUrl http://localhost:8086 -OtpBaseUrl http://localhost:8081/otp`
