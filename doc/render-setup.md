# Render deployment setup

This project can be deployed on Render with:

- `rotransit-backend` as Web Service
- `rotransit-otp` as Private Service
- `rotransit-postgres` as managed PostgreSQL

Use the root `render.yaml` blueprint to create all resources.

## Environment assumptions

- Backend reads `PORT` (fallback `SERVER_PORT`) from runtime env.
- Backend DB values are injected from Render managed Postgres.
- OTP stores graph/data on a persistent disk mounted at `/var/opentripplanner`.

## Health checks

- Backend: `/api/health`
- OTP: configure service health on `/otp/routers/default` in Render dashboard.

## First deploy notes

1. Push repository to Git provider connected to Render.
2. Create Blueprint instance from `render.yaml`.
3. Confirm DB is provisioned and backend env vars are resolved from database properties.
4. Verify backend can read cities and route-search endpoint:
   - `GET /api/cities`
   - `GET /api/routes/search?...`
