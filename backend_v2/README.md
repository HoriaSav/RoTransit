# RoTransit backend (`backend_v2`)

[![Backend CI](https://github.com/HoriaSav/RoTransit/actions/workflows/backend.yml/badge.svg?branch=horia/spring-backend-rebuild)](https://github.com/HoriaSav/RoTransit/actions/workflows/backend.yml)

This is the backend of RoTransit, a Spring Boot service that keeps an up-to-date GTFS feed for each Romanian city and serves it to clients. The server's job is deliberately small. It gets the official timetable data, checks when it starts and expires, refreshes it before it goes stale and hands out the zip. Clients do the heavy work (search, timetables, routing) on the device.

For what RoTransit is as a whole, see the [project README](../README.md).

## Status

- `backend_v2` is a ground-up rebuild of the old OTP-based API (see [Legacy](#legacy)). It's under active development on `horia/spring-backend-rebuild` and isn't deployed yet.
- 13 city feeds are seeded. Download, versioning, future-start versions, scheduled refresh, file cleanup, the public API and the authenticated admin API all work.
- An automated test suite runs on every push through GitHub Actions against a real Postgres.

## How it works

### Data model

Flyway creates the tables in the `feeds` schema (`V1`) and seeds the 13 cities (`V2`). Hibernate only validates the schema (`ddl-auto=validate`).

| Table | What it holds |
|-------|---------------|
| `city` | A city we serve, e.g. Brasov |
| `feed` | One GTFS dataset (transit network) for a city. Its `name` is what the API calls `companyName` |
| `feed_source` | Where a feed is downloaded from: `kind` is `mobilitydb` (`ref` is a Mobility Database id like `mdb-2143`) or `url` (`ref` is the URL). Only the priority-1 source is used today |
| `feed_version` | One row per download attempt: `status` (`current` / `upcoming` / `old` / `failed`), `file_path`, `sha256`, `starts_on`, `expires_on`, `downloaded_at`, `served_from`, `checked_at` |
| `operator` | The operators (`agency.txt` rows) inside one downloaded version |

The database itself allows at most one `current` and one `upcoming` version per feed (partial unique indexes). `sha256` is deliberately not unique: a feed can go back to an older file, and both rows then share the same file on disk.

### Download

- A Mobility Database source is fetched from `https://files.mobilitydatabase.org/{sourceId}/latest.zip` into a temp file. A response other than 200 or an invalid zip is rejected with `502` and stored as a `failed` row, which never replaces the current version.
- The service computes the file's sha256 and reads its dates: the start from `feed_info.txt` (`feed_start_date`), falling back to `calendar.txt` (`start_date`) and `calendar_dates.txt` (`date`); the expiry the same way with `feed_end_date`, `end_date` and the latest `date`. Columns are found by header name, a UTF-8 BOM is stripped and unparseable dates are skipped. Operators are read from `agency.txt`.
- If the sha256 matches the current or upcoming version, nothing is saved and the download is reported as **unchanged**. Its `checked_at` is set instead.
- Otherwise the file is moved to `feeds/{feedId}/{sha256}.zip`, so a new download never overwrites an older one.

### Versions

| Downloaded file | Becomes |
|-----------------|---------|
| No start date, or a start date today or in the past | `current` (the previous current becomes `old`) |
| Start date in the future, and the feed has no servable current version | `current` (a future feed beats no feed) |
| Start date in the future, and the feed has a current version | `upcoming` (the current one keeps being served; an earlier upcoming becomes `old`) |

An upcoming version is promoted to current on its start date by the 04:00 job, once at startup (in case the server was down at 04:00), or by hand with `POST /admin/feeds/{id}/promote`. `served_from` records when a version became current.

"Today" comes from one app-wide `Clock` set to `Europe/Bucharest`, whatever zone the server runs in.

### Scheduled refresh

Every day at 04:00 (server time), `FeedUpdateJob` first cleans up orphan files, then promotes due upcoming versions, then re-downloads any feed that is missing its file on disk, has no known expiry, or whose newest version (upcoming if there is one) expires within 7 days. A feed whose source sent the same file again less than 24 hours ago is skipped. A failure affects only that feed, and the job moves on.

### Cleanup

- **Retention:** files are kept for the current version, the upcoming version and the old version that was served most recently. Older files are deleted and their `file_path` cleared; the rows stay. A file shared with a kept version is never deleted.
- **Failed attempts:** only the newest 5 `failed` rows per feed are kept.
- **Orphan sweep:** at startup and before each job run, files under `feeds/` that no database row points to are deleted once they are older than 1 hour (including leftover `.part` temp files). Symlinks are never followed or deleted.

### Safe file serving

File paths are never exposed in JSON, and the file endpoints only serve files whose real path (after following symlinks) is inside `feeds/`.

### Seeded feeds

| City | Feed (`companyName`) | Source id |
|------|----------------------|-----------|
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

Java 21 · Spring Boot 4.1 (Web, Data JPA, Security, Actuator) · PostgreSQL 16 · Flyway · Hibernate (`ddl-auto=validate`) · Apache Commons CSV · JUnit 5 + Mockito · JaCoCo · Maven wrapper · GitHub Actions

## API

### Public (no auth)

| Method | Path | Returns |
|--------|------|---------|
| `GET` | `/api/feeds` | List of feeds sorted by id: `id`, `cityName`, `companyName`, `operators` (names from the current version), `current` and `upcoming` (each `sha256`, `startsOn`, `expiresOn`, `downloadedAt`, or `null`) |
| `GET` | `/api/feeds/{id}/file` | The current GTFS zip (`application/zip`, as `{id}.zip`); `404` if there is none |
| `GET` | `/api/feeds/{id}/file/upcoming` | The upcoming GTFS zip (as `{id}-upcoming.zip`); `404` if there is none |

Both file endpoints send an `ETag` equal to the file's sha256 (the same value `/api/feeds` shows). A request with a matching `If-None-Match` gets `304 Not Modified` and no body. A client can compare its stored sha with `current.sha256` and download only when they differ, and can fetch the upcoming file early to switch on its start date, even offline.

### Admin (`/admin/**`, HTTP Basic, role `ADMIN`)

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/admin/feeds` | Status list: `id`, `cityName`, `companyName`, `status` (`new` / `downloaded` / `failed`), `downloadedAt`, `expiresOn`, `daysLeft`, `upcomingStartsOn`. Sorted by expiry, unknown expiry first |
| `GET` | `/admin/feeds/{id}` | One feed: `id`, `cityName`, `companyName`, `sourceId`, `sourceUrl`, `status`, `downloadedAt`, `startsOn`, `expiresOn`, `upcoming` |
| `POST` | `/admin/feeds` | Add a feed. Body: `{"cityName", "companyName", "sourceId"}` (`sourceId` is a Mobility Database id). Returns the feed |
| `POST` | `/admin/feeds/{id}/download` | Download one feed now. Returns the feed plus `unchanged` (`true` if the source sent the file we already had) |
| `POST` | `/admin/feeds/{id}/promote` | Switch to the upcoming version now. `404` "feed has no upcoming version" if there is none |
| `GET` | `/admin/feeds/{id}/expires` | Expiry date read from the stored zip |
| `POST` | `/admin/feeds/update` | Run the update job now and stream one line per city (`text/plain`) as each one finishes |

`status` is `failed` when the newest attempt failed; a current version, if there is one, is still served.

Security is stateless with no sessions and CSRF disabled. A request to `/admin/**` without valid credentials gets `401`, a non-admin user gets `403`, and any path outside `/api/**` and `/admin/**` is denied. An unknown feed id returns a `404` [ProblemDetail](https://www.rfc-editor.org/rfc/rfc9457) (`application/problem+json`).

## Run locally

**Prerequisites:** JDK 21 and Docker. Maven comes with the wrapper (`./mvnw`).

**1. Start Postgres** from the repo root (container `rotransit-postgres` on `localhost:5432`, DB `rotransit`, user `admin`):

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

[`.env.example`](.env.example) lists the variables. Spring Boot doesn't read `.env` by itself, so load it through your IDE's run configuration or export the variables in your shell. Use single quotes around a bcrypt hash so the shell doesn't expand its `$` characters.

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

Tests use their own admin password (`src/test/resources/config/application.properties`) and a fixed clock, so they never depend on your real `SPRING_SECURITY_PASSWORD` or today's date. JaCoCo writes a coverage report to `target/site/jacoco`.

| Area | Test classes |
|------|--------------|
| GTFS date detection | `FeedServiceExpireDateTest` |
| Download, zip validation, unchanged files, versions | `FeedServiceDownloadTest` |
| Retention | `FeedServiceRetentionTest` |
| Orphan sweep | `FeedServiceSweepTest` |
| Scheduled update job and promotion | `FeedUpdateJobTest` |
| Versions against the real database | `FeedVersionSwitchTest` |
| Controllers, persistence, error handling | `FeedControllerTest`, `AdminControllerTest`, `AdminRoutesContextTest`, `CreateFeedPersistenceTest`, `GlobalExceptionHandlerTest` |
| Security (auth, roles, denied paths) | `SecurityConfigTest`, `AdminRoleSecurityTest` |
| Application context | `RoTransitApplicationTests` |

## CI

| Workflow | What it does |
|----------|--------------|
| [`backend.yml`](../.github/workflows/backend.yml) | Runs on every push and pull request that touches `backend_v2/**` or the workflow. Starts a `postgres:16` service container, sets up Temurin JDK 21 with a Maven cache and runs `./mvnw -B test`. Uploads the JaCoCo report as the `jacoco-report` artifact and writes a coverage summary to the run page. The badge at the top shows the latest result |
| [`codeql.yml`](../.github/workflows/codeql.yml) | CodeQL security analysis of `backend_v2` on pushes and pull requests that touch it, and weekly on Mondays |
| [`dependabot.yml`](../.github/dependabot.yml) | Weekly update PRs for the Maven dependencies and the GitHub Actions. GitHub only reads it from the default branch |

## Repo layout

| Path | What it is |
|------|------------|
| `backend_v2/` | **Current backend** (this folder) |
| `.github/` | CI, CodeQL and Dependabot |
| `db/postgres/` | Postgres env template and init script used by the `db` compose service |
| `docker-compose.yml` | `db` is used by `backend_v2`; the other services are legacy |
| `frontend/` | Flutter mobile app |
| `backend/`, `otp/`, `cloudflare/`, `scripts/server`, `scripts/db`, `scripts/backend` | Legacy stack, see below |

## Legacy

The first version of RoTransit was a full server stack. `backend/` was a Spring Boot 3.3 API with route search, stop search, timetables, saved routes, cities and an offline-pack endpoint, backed by **OpenTripPlanner** (`otp/`) for routing and a Postgres GTFS read model (`scripts/db`, `db/postgres/init`). It was exposed publicly through a **Cloudflare** tunnel (`cloudflare/`, `scripts/server`). `backend_v2` replaces it with a much smaller feed-serving service. The old code is kept for reference and isn't built by CI.

Note: on a fresh volume, `db/postgres/init/001_init.sql` still creates the old stack's tables in the `public` schema. `backend_v2` only uses the `feeds` schema, so they don't interfere.
