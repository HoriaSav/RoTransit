# Database Setup and GTFS Import

This folder owns database bootstrap and GTFS read-model import.

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

Python script:

```powershell
python scripts/db/import_gtfs_to_db.py --gtfs "otp/gtfs/ro-ratbv.zip" --city-id <CITY_UUID>
```

PowerShell wrapper:

```powershell
.\scripts\db\import_gtfs_to_db.ps1 -CityId <CITY_UUID> -GtfsPath "otp/gtfs/ro-ratbv.zip"
```

If needed, pass DB URL explicitly:

```powershell
python scripts/db/import_gtfs_to_db.py --gtfs "otp/gtfs/ro-ratbv.zip" --city-id <CITY_UUID> --db-url "postgresql://admin:rotransit_password@localhost:5433/rotransit"
```

## 4) Refresh / reimport

Re-run the import command. Import is city-scoped and replaces old GTFS rows for that city.

## 5) Notes

- Required GTFS files: `stops.txt`, `routes.txt`, `trips.txt`, `stop_times.txt`
- Optional GTFS files: `calendar.txt`, `calendar_dates.txt`
- If you get missing table errors, apply `db/postgres/init/001_init.sql` once to current DB volume before importing.
