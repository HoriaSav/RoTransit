# Database Setup and GTFS Import

This folder owns database bootstrap and GTFS read-model import.

## Automatic GTFS import (Docker Compose)

Starting the **full stack** from the repo root runs the **`gtfs-import`** service once after Postgres is healthy and **before** **`app`** starts.

1. Put the feed zip at **`otp/gtfs/ro-ratbv.zip`** (mounted read-only as `/gtfs/ro-ratbv.zip` in the importer).
2. The importer uses **`--city-name Brasov`** and **`--country Romania`** so you do not need a UUID from `/api/cities`.
3. **`GTFS_IMPORT_IF_EMPTY=1`** (set in Compose): if `gtfs_routes` already has rows for that city, the job **skips** the heavy import and exits 0 (fast `docker compose up` restarts).
4. If the zip is **missing**, `gtfs-import` fails and **`app` will not start** until you add the file.

```powershell
docker compose up -d --build
```

**Force a full reimport** after replacing the zip (or to refresh data), from the repo root with **`db` already running**:

```powershell
docker compose run --rm -e GTFS_IMPORT_FORCE=1 -e GTFS_IMPORT_IF_EMPTY=0 gtfs-import --gtfs /gtfs/ro-ratbv.zip --city-name Brasov --country Romania
```

This reuses the service image, `DB_URL`, and `./otp/gtfs` mount from Compose.

## 1) First-time bootstrap

Run from repository root:

```powershell
docker compose up -d db
docker compose exec db psql -U admin -d rotransit -f /docker-entrypoint-initdb.d/001_init.sql
```

Verify tables:

```powershell
docker compose exec db psql -U admin -d rotransit -c "\dt"
docker compose exec db psql -U admin -d rotransit -c "\dt gtfs_*"
```

## 2) Get city id

```powershell
Invoke-RestMethod -Uri "http://localhost:8085/api/cities" | ConvertTo-Json -Depth 6
```

Use the Brasov `id` value for GTFS import.

## 3) Import GTFS to Postgres read model

Python script (by city UUID):

```powershell
python scripts/db/import_gtfs_to_db.py --gtfs "otp/gtfs/ro-ratbv.zip" --city-id <CITY_UUID>
```

By city name (no UUID):

```powershell
python scripts/db/import_gtfs_to_db.py --gtfs "otp/gtfs/ro-ratbv.zip" --city-name Brasov --country Romania
```

Skip import when routes already exist (`--if-empty`, or env `GTFS_IMPORT_IF_EMPTY=1`); override with `--force` or `GTFS_IMPORT_FORCE=1`.

PowerShell wrapper:

```powershell
.\scripts\db\import_gtfs_to_db.ps1 -CityId <CITY_UUID> -GtfsPath "otp/gtfs/ro-ratbv.zip"
```

If needed, pass DB URL explicitly:

```powershell
python scripts/db/import_gtfs_to_db.py --gtfs "otp/gtfs/ro-ratbv.zip" --city-id <CITY_UUID> --db-url "postgresql://admin:rotransit_password@localhost:5432/rotransit"
```

## Cleanup for older databases

Volumes created before accounts and the Bucharest placeholder city were removed still have the `users`, `saved_routes`, `favorite_stops` tables and the Bucharest row (so `/api/cities` still lists it). Run once, after a backup:

```powershell
docker compose exec -T db psql -U admin -d rotransit < db/postgres/cleanup/2026-09_drop_accounts_and_bucharest.sql
```

## 4) Refresh / reimport

Re-run the import command without `--if-empty`, or pass **`--force`**. Import is city-scoped and replaces old GTFS rows for that city.

## 5) Notes

- Required GTFS files: `stops.txt`, `routes.txt`, `trips.txt`, `stop_times.txt`
- Optional GTFS files: `calendar.txt`, `calendar_dates.txt`
- If you get missing table errors, apply `db/postgres/init/001_init.sql` once to current DB volume before importing.
