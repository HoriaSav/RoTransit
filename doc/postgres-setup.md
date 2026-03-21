# 1. Prerequisites
- Docker Desktop installed and running
- `docker-compose.yml` present in repo root
- `db/postgres/.env` configured with:
  - `POSTGRES_DB`
  - `POSTGRES_USER`
  - `POSTGRES_PASSWORD`
- Port `5432` available on your machine (or update compose port mapping)

# 2. Start PostgreSQL

From repo root:
```
docker compose up -d db
```

What this does:
- starts service `db` from `docker-compose.yml`
- creates/uses volume `rotransit_postgres_data`
- runs scripts from `db/postgres/init` on first initialization only

# 3. Verify it is running
1. Check container status:
```
docker compose ps db
```

2. Check logs:
```
docker compose logs -f db
```

# 4. Stop commands

- Stop only Postgres:
```
docker compose stop db
```

- Start again after stop:
```
docker compose start db
```

- Stop and remove container (keep data volume):
```
docker compose down
```

# 5. Initialize with a new volume (fresh database)

Use this when you want a clean DB and to rerun init scripts:
```
docker compose down -v
docker compose up -d db
```

Notes:
- `down -v` removes all compose volumes, including Postgres data.
- SQL files in `db/postgres/init` run only when a new data directory is created.
