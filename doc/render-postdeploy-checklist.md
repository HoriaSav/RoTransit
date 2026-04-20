# Render post-deploy checklist

Run this after every Render deploy.

## 1) Service health

- Backend service status is healthy.
- OTP service status is healthy.
- Postgres service is available.

## 2) Backend API smoke

Use your public backend URL:

- `GET /api/health` -> 200 and `status=ok`
- `GET /api/cities` -> 200 and non-empty list
- `GET /api/routes/search` with valid params -> 200
- `GET /api/stops/nearby` with valid params -> 200

## 3) Saved route flow

- `POST /api/routes/save` -> 201 and id present
- `GET /api/routes/saved?deviceUserId=<id>` -> created route returned
- `DELETE /api/routes/saved/{routeId}?deviceUserId=<id>` -> 204

## 4) Migration and startup checks

In backend logs verify:

- Flyway started successfully.
- No pending migration errors.
- App started on expected port (`PORT` env).

## 5) OTP connectivity check

Backend logs should not show upstream OTP connection failures during route or stops calls.

## 6) Restart safety

- Trigger a backend restart from Render.
- Re-run health + one route search call.
- Confirm results are still correct.
