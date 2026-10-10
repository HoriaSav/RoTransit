# RoTransit technical spec

Living technical contract for the prototype. Product-facing text lives in the root [README](../README.md). Architecture board: [RoTransit OS](https://app.notion.com/p/3d56691920958188b40ec30fc4bc2a59) (Notion Idei). Visual canvas (open in a browser, not a Notion page): [`docs/rotransit-os.html`](rotransit-os.html).

**Status:** prototype. One city with real data (Brașov / RATBV). Multi-city is sketched in the database, not product-complete.

---

## 1. Product in one sentence

RoTransit is an offline stop map and timetable companion for Brașov: find a stop, see its next scheduled departures, browse line timetables. No trip planner in the app.

## 2. Current user surface (Flutter)

Tabs (bottom nav):

| Tab | What it does |
|-----|----------------|
| Map | Brașov stops from the bundled pack; tap or search a stop for its board of scheduled departures |
| Timetable | Browse lines, stops, week timetables (from the bundled pack) |
| Favorites | Starred stops and lines stored on the phone |

Settings opens from the gear on the map: theme, language (EN / RO / DE), city, data as of, fares link, app version.

Primary happy path (Brașov / RATBV):

1. Open the map, tap (or search) a stop.
2. The stop board lists the next scheduled departures.
3. Open a line to see its timetable, or star the stop / line.

There is no sign-in. Favorites stay in SQLite on the phone. Extra cities and accounts wait until this loop is boringly reliable.

## 3. System architecture

```
Phone (Flutter)
  ├── flutter_map (tiles, stop pins, location)
  ├── bundled Brașov pack (assets/data/brasov_companion.sqlite.gz)
  ├── SharedPreferences (favorites, settings)
  └── HTTPS (city list, non-Brașov only) ──► Cloudflare Tunnel ──► Spring Boot :8085
                                          ├── PostgreSQL (cities, GTFS read model)
                                          └── OpenTripPlanner :8080 (OSM + GTFS graph)
```

Compose services (`docker-compose.yml`): `db` → `gtfs-import` (once) → `otp` + `app` → `cloudflared`.

Data feeds:

- **GTFS** zip `otp/gtfs/ro-ratbv.zip` — used twice: OTP routing graph, and a Postgres read model for catalog / offline packs.
- **OSM** PBF under `otp/osm/` (build config currently names `romania.osm.pbf`).

Time zone for search windows: `Europe/Bucharest`.

## 4. Tech stack

| Layer | Choice | Role |
|-------|--------|------|
| Mobile | Flutter 3.x, Dart 3.3+, Riverpod | UI, local-first state |
| HTTP | Dio | API client |
| Maps | flutter_map + tile caching | Map and overlays |
| Local DB | sqflite | Bundled Brașov pack (read-only) + legacy offline tables |
| API | Java 21, Spring Boot 3.3 | REST facade |
| Persistence | PostgreSQL 16, JPA (`ddl-auto: none`) | Schema from SQL init |
| Routing engine | OpenTripPlanner 2.x | Itineraries from GTFS + OSM |
| Ingress | Cloudflare Tunnel | Public `https://api.horiasavin.me` |
| GTFS import | Python (`scripts/db/import_gtfs_to_db.py`) | Fill `gtfs_*` tables |

## 5. HTTP API (backend)

Base path `/api`. Public default: `https://api.horiasavin.me`. Local: `http://localhost:8085`. Android emulator: `http://10.0.2.2:8085`.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/health` | Liveness |
| GET | `/api/cities` | Supported cities (id, name, country) |
| GET | `/api/routes/search` | (not called by the app) Journey plan via OTP (`cityId`, `origin`, `destination`, `serviceDate`, `serviceTime`, pagination, optional geometry) |
| GET | `/api/stops/nearby` | (not called by the app) Stops around lat/lon |
| GET | `/api/stops/search` | (not called by the app) Stop name search |
| GET | `/api/stops/resolve-for-route` | (not called by the app) Disambiguate destination when several stops share a name |
| GET | `/api/buses` | Line catalog for a city |
| GET | `/api/buses/{routeId}/stops` | Stops on a line |
| GET | `/api/buses/{routeId}/timetable` | Departures at a stop |
| GET | `/api/buses/offline-pack-meta` | (not called by the app) Fingerprint of the weekly pack |
| GET | `/api/buses/offline-pack` | (not called by the app) JSON blob for offline catalog/timetables |

Flutter `API_BASE_URL` dart-define: `frontend/lib/src/core/config/api_config.dart`. The app always talks to the real API.

## 6. Data model (Postgres)

Init: `db/postgres/init/001_init.sql`.

**Product tables**

- `cities` — name, country, `otp_base_url`. Seeded Brașov only (`93715d42-5523-4195-8743-53b6819488c9`).

**GTFS read model** (city-scoped): `gtfs_stops`, `gtfs_routes`, `gtfs_trips`, `gtfs_stop_times`, `gtfs_calendar`, `gtfs_calendar_dates`.

OTP does **not** query these tables for routing; it uses its own graph built from the zip + OSM.

## 7. Data model (SQLite on device)

`frontend/lib/src/local/local_db.dart` (version 6):

- `offline_transit_*` — legacy server-pack tables, emptied at startup; no reader (kept for a possible multi-city return)
- `saved_routes` — legacy journeys, left in place on upgrade (no reader)

Favorites (stops, lines) are stored in SharedPreferences by `favorite_stops_repository.dart`. Brașov timetables come from the bundled pack (`companion_catalog.dart`), extracted to its own SQLite file.

Bundled pack (schema 3, built by `scripts/data/build_brasov_companion_pack.py`): `stops`, `routes`, `route_stops`, `departures` (with `service_id`), `services` (GTFS calendar weekdays + date range), `service_exceptions` (calendar_dates), `trips` (first/last stop names), `day_overrides`, `meta`. The stop board keeps only departures whose service runs on that calendar date (calendar + exceptions); after the feed's last service date it says the timetable data has ended. The weekly Mon–Fri / Sat / Sun tabs always show the regular pattern (a holiday in the current week does not change them).

## 8. Routing behaviour

`RouteService` (OTP search / stop resolve) + `TransitCatalogService` (buses, timetables, offline pack) + `OtpHttpClient`:

- Prefer transit over long walks (strict max walk ~1 km, then a relaxed pass, then GraphQL fallback on OTP 2.9+).
- Incremental time-window search (15-minute slices, in-memory session, merged itinerary cap).
- Walk-only or oversized walk legs are filtered when transit exists.

OTP configs: `otp/build-config.json`, `otp/router-config.json`.

## 9. Offline

Brașov works fully offline from the bundled pack. Settings shows the manifest `data_as_of`. Holidays come from GTFS `calendar_dates` (pack table `day_overrides`). There is no pack download in the app; the server offline-pack endpoints are unused.

## 10. Known prototype debt (why it feels chaotic)

1. **No accounts** — favorites stay on the device. There is no backend user or saved-route API.
2. **One city** — Brașov / RATBV only. Other catalog cities are ignored in the app (`isCityAvailable`).
3. **Placeholder city UUID** — retired. Missing ids fall back to Brașov `93715d42-5523-4195-8743-53b6819488c9` (`kBrasovCityId`).
4. **Favorites** — stops and lines, local SQLite only.
5. **Ideas vs code** — Notion *Idei* has many rows all titled “RoTransit”; architecture lives in this spec + `docs/rotransit-os.html`.

Treat this list as the cleanup backlog, not as extra features.

## 11. Suggested build order (planning)

Do **not** start with more cities. Stabilize one loop.

1. **Lock the product slice** — Brașov only: map → stop board → line timetable. Everything else is secondary.
2. **Single source of city id** — one Brașov UUID everywhere; remove placeholder ids.
3. **Decide maps** — keep one library for the main map.
4. **Offline as a feature** — document what works offline (catalog/timetable) vs what does not (live OTP).

## 12. Local run (operators)

Prerequisites: Docker, GTFS zip, OSM PBF, Cloudflare token in `cloudflare/.env` for public API.

```bash
./scripts/server/setup.sh
./scripts/server/up.sh --build -d
```

Flutter: open `frontend/` (not the repo root). Details: [frontend/README.md](../frontend/README.md).

GTFS import: [db/README.md](../db/README.md).
