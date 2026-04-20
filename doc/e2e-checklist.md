# End-to-end checklist

## Single-command gate (recommended)

Run from repo root:

`powershell -ExecutionPolicy Bypass -File scripts/backend/run-local-gate.ps1`

This command runs version checks, service readiness, OTP discovery, backend/API smokes, DB consistency checks, and backend tests.

## Backend verification

1. Start services (`db`, `otp`, `app`) from `docker-compose.yml`.
2. Verify health:
   - `GET http://localhost:8085/api/health`
3. Verify cities:
   - `GET http://localhost:8085/api/cities`
4. Verify route search:
   - `GET /api/routes/search?cityId=<city_uuid>&origin=45.650,25.610&destination=45.640,25.600&serviceDate=2026-03-27&serviceTime=08:30:00&passengerCount=1`
5. Verify nearby stops:
   - `GET /api/stops/nearby?cityId=<city_uuid>&lat=45.645&lon=25.589&radiusMeters=500`
6. Verify saved routes:
   - `POST /api/routes/save`
   - `GET /api/routes/saved?deviceUserId=guest-device-1`
   - `DELETE /api/routes/saved/{routeId}?deviceUserId=guest-device-1`

## Test suite

Run:

`backend/./mvnw test`

Expected:

- `CityControllerIntegrationTest` pass
- `RouteControllerIntegrationTest` pass
- `SavedRouteControllerIntegrationTest` pass

## Release gates

- Pre-push local gate: see `doc/pre-push-gate.md`
- Render post-deploy gate: see `doc/render-postdeploy-checklist.md`

## Frontend note

Frontend has been intentionally moved out of this repository and should be implemented in a separate repo.

Backend APIs in this repo are ready for frontend integration:

- `GET /api/cities`
- `GET /api/routes/search`
- `GET /api/stops/nearby`
- `POST /api/routes/save`
- `GET /api/routes/saved`
- `DELETE /api/routes/saved/{routeId}`
