# RoTransit

[![Backend CI](https://github.com/HoriaSav/RoTransit/actions/workflows/backend.yml/badge.svg?branch=horia/spring-backend-rebuild)](https://github.com/HoriaSav/RoTransit/actions/workflows/backend.yml)

RoTransit is a public-transport project for Romanian cities. This README covers the backend (`backend_v2/`), a Spring Boot service that keeps an up-to-date GTFS feed for each city and serves it to clients. The server's job is deliberately small. It gets the official timetable data, checks when it expires, refreshes it before it goes stale and hands out the zip. Clients do the heavy work (search, timetables, routing) on the device.

> The Flutter mobile app lives in `frontend/` and isn't covered here yet.

## Status

- `backend_v2` is a ground-up rebuild of the old OTP-based API (see [Legacy](#legacy)). It's under active development on `horia/spring-backend-rebuild` and isn't deployed yet.
- 13 city feeds are seeded. Download, expiry detection, scheduled refresh, the public API and the authenticated admin API all work.
- 128 automated tests run on every push through GitHub Actions against a real Postgres.

## Architecture

- **One table, `feeds.feed`**: city, operator, Mobility Database source id, status (`new` / `downloaded` / `failed`), local file path, download time and expiry date. Flyway creates it (`V1`) and seeds it (`V2`).
- **Download**: `https://files.mobilitydatabase.org/{sourceId}/latest.zip` goes to a temp file. A response other than 200 or an invalid zip is rejected with `502`. A good zip is moved atomically to `feeds/{id}.zip`, so a failed download never replaces a good file.
- **Expiry detection**: the service reads the latest date in `feed_info.txt` (`feed_end_date`), falling back to `calendar.txt` (`end_date`) and then `calendar_dates.txt` (`date`). Columns are found by header name, a UTF-8 BOM is stripped and unparseable dates are skipped.
- **Scheduled refresh**: every day at 04:00 (server time), `FeedUpdateJob` re-downloads any feed that is missing on disk, has no known expiry, or expires within 7 days. A failure marks only that feed `failed` and the job moves on to the next one.
- **Safe file serving**: `localPath` is never exposed in JSON, and `/api/feeds/{id}/file` only serves files whose real path (after following symlinks) is inside `feeds/`.

### Seeded feeds

| City | Operator | Source id |
|------|----------|-----------|
| Brasov | RATBV | mdb-2143 |
| Bucuresti | STB | mdb-2098 |
| Buzau | CJ-Buzau | mdb-3179 |
| Cluj-Napoca | CTP-Cluj | mdb-2121 |
| Constanta | CT-Bus | mdb-2100 |
| Craiova | RAT-Craiova | mdb-2115 |
| Iasi | CTP-Iasi | mdb-2116 |
| Oradea | OTL | mdb-2101 |
| Ploiesti | TCE-Ploiesti | mdb-2108 |
| Sibiu | Tursib | mdb-2099 |
| Sinaia | TU-Sinaia | mdb-2114 |
| Targoviste | SPM-Targoviste | mdb-2107 |
| Timisoara | SMTT | mdb-2868 |

## Tech stack

Java 21 · Spring Boot 4.1 (Web, Data JPA, Security, Actuator) · PostgreSQL 16 · Flyway · Hibernate (`ddl-auto=validate`) · JUnit 5 + Mockito · Maven wrapper · GitHub Actions

## API

### Public (no auth)

| Method | Path | Returns |
|--------|------|---------|
| `GET` | `/api/feeds` | List of feeds: `id`, `cityName`, `companyName` |
| `GET` | `/api/feeds/{id}/file` | The GTFS zip (`application/zip`, as an attachment); `404` if it isn't downloaded yet |

### Admin (`/admin/**`, HTTP Basic, role `ADMIN`)

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/admin/feeds` | Status list with `status`, `downloadedAt`, `expiresOn`, `daysLeft`, sorted by expiry with unknown expiry first |
| `GET` | `/admin/feeds/{id}` | One feed |
| `POST` | `/admin/feeds` | Add a feed (`{"cityName", "companyName", "sourceId"}`) |
| `POST` | `/admin/feeds/{id}/download` | Download one feed now |
| `GET` | `/admin/feeds/{id}/expires` | Expiry date read from the stored zip |
| `POST` | `/admin/feeds/update` | Run the update job now and stream one line per city (`text/plain`) as each one finishes |

Security is stateless with no sessions and CSRF disabled. A request to `/admin/**` without valid credentials gets `401`, and any path outside `/api/**` and `/admin/**` is denied. An unknown feed id returns a `404` [ProblemDetail](https://www.rfc-editor.org/rfc/rfc9457) (`application/problem+json`).

## Run locally

**Prerequisites:** JDK 21 and Docker. Maven comes with the wrapper (`./mvnw`).

**1. Start Postgres** (container `rotransit-postgres` on `localhost:5432`, DB `rotransit`, user `admin`):

```bash
cp db/postgres/.env.example db/postgres/.env   # then set POSTGRES_PASSWORD
docker compose up -d db
```

Only start the `db` service. The other services in `docker-compose.yml` belong to the legacy stack. Flyway creates the `feeds` schema on first start of the app.

**2. Set environment variables** (the app has no defaults for these):

| Variable | Meaning |
|----------|---------|
| `SPRING_DATASOURCE_PASSWORD` | Must match `POSTGRES_PASSWORD` from `db/postgres/.env` |
| `SPRING_SECURITY_PASSWORD` | Password for the `admin` user. It can be plaintext or, better, a bcrypt hash with an id prefix: `{bcrypt}$2a$10$...` |

`backend_v2/.env.example` lists the variables. Spring Boot doesn't read `.env` by itself, so load it through your IDE's run configuration or export the variables in your shell. Use single quotes around a bcrypt hash so the shell doesn't expand its `$` characters.

**3. Run:**

```bash
cd backend_v2
./mvnw spring-boot:run        # http://localhost:8080
```

**4. Try it** (`jq` is optional and only pretty-prints the output):

```bash
# Public
curl -s localhost:8080/api/feeds | jq
curl -OJ localhost:8080/api/feeds/1/file

# Admin: use the plaintext password here, not the hash
curl -s -u admin:'<password>' localhost:8080/admin/feeds | jq
curl -N -X POST -u admin:'<password>' localhost:8080/admin/feeds/update
```

Seeded feeds start as `new` with no file. Run `/admin/feeds/update` once (or wait for the 04:00 job) to download them into `backend_v2/feeds/`, which is gitignored.

## Tests

```bash
cd backend_v2
./mvnw test     # needs Postgres running and SPRING_DATASOURCE_PASSWORD set
```

Tests use their own admin password (`src/test/resources/config/application.properties`), so they never depend on your real `SPRING_SECURITY_PASSWORD`.

| Area | Test classes | Tests |
|------|--------------|------:|
| GTFS expiry detection | `FeedServiceExpireDateTest` | 21 |
| Download & zip validation | `FeedServiceDownloadTest` | 9 |
| Scheduled update job | `FeedUpdateJobTest` | 20 |
| Controllers, persistence, error handling | `FeedControllerTest`, `AdminControllerTest`, `AdminRoutesContextTest`, `CreateFeedPersistenceTest`, `GlobalExceptionHandlerTest` | 49 |
| Security (auth, roles, denied paths) | `SecurityConfigTest`, `AdminRoleSecurityTest` | 28 |
| Application context | `RoTransitApplicationTests` | 1 |
| **Total** | | **128** |

## CI

[`.github/workflows/backend.yml`](.github/workflows/backend.yml) runs on every push and pull request that touches `backend_v2/**` or the workflow itself. It starts a `postgres:16` service container, sets up Temurin JDK 21 with a Maven cache and runs `./mvnw -B test`. The badge at the top shows the latest result.

## Repo layout

| Path | What it is |
|------|------------|
| `backend_v2/` | **Current backend** (Spring Boot 4.1, Java 21) |
| `.github/workflows/backend.yml` | Backend CI |
| `db/postgres/` | Postgres env template and init script used by the `db` compose service |
| `docker-compose.yml` | `db` is used by `backend_v2`; the other services are legacy |
| `frontend/` | Flutter mobile app (not covered here yet) |
| `backend/`, `otp/`, `cloudflare/`, `scripts/server`, `scripts/db`, `scripts/backend` | Legacy stack, see below |

## Legacy

The first version of RoTransit was a full server stack. `backend/` was a Spring Boot 3.3 API with route search, stop search, timetables, saved routes, cities and an offline-pack endpoint, backed by **OpenTripPlanner** (`otp/`) for routing and a Postgres GTFS read model (`scripts/db`, `db/postgres/init`). It was exposed publicly through a **Cloudflare** tunnel (`cloudflare/`, `scripts/server`). `backend_v2` replaces it with a much smaller feed-serving service. The old code is kept for reference and isn't built by CI.

Note: on a fresh volume, `db/postgres/init/001_init.sql` still creates the old stack's tables in the `public` schema. `backend_v2` only uses the `feeds` schema, so they don't interfere.
