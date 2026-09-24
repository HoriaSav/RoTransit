# RoTransit

Public-transport companion for Romanian cities. The **Brașov Map companion** branch focuses on an on-device stop map and schedule boards (no RoTransit server required for pins or departures). Trip search / OTP routing remains optional and still needs the API when used.

The working city is **Brașov (RATBV)**. There is no sign-in: saved trips stay on the phone. Extra cities are out of scope until this loop is solid.


## Brașov offline companion pack

Shipped in the app as `frontend/assets/data/brasov_companion.sqlite.gz` (stops, lines, scheduled departures).

- Built from RATBV GTFS (`otp/gtfs/ro-ratbv.zip`, typically gitignored) via `scripts/data/build_brasov_companion_pack.py`.
- Map stop boards and Timetable line boards read this pack locally. Map tiles may still use the network.
- Settings shows **data as of** from the pack manifest. Favorites (stops/lines) stay on-device only.
- Directions / live GPS ETAs are stubbed or out of scope on this branch.

## What you can do today

- Plan a journey between stops (or map picks) for a date and time
- Compare itineraries on the map
- Browse bus lines and stop timetables
- Save trips and lines on the device
- Download a weekly pack of bus lines and stop timetables (Search A→B still needs the internet)
- Switch language (English, Romanian, German) and theme

Door-to-door routing still needs the API. The offline pack covers catalog and timetables, not a full local trip planner.

## Stack (short)

Phone: **Flutter**. API: **Spring Boot**. Routing: **OpenTripPlanner** (GTFS + OpenStreetMap). Data: **PostgreSQL**. Public URL via a **Cloudflare** tunnel.

How the pieces connect: [`docs/TECHNICAL_SPEC.md`](docs/TECHNICAL_SPEC.md). Visual board (open in a browser): [`docs/rotransit-os.html`](docs/rotransit-os.html).

## Run it

**API (Docker)** — GTFS zip at `otp/gtfs/ro-ratbv.zip`, OSM `.pbf` under `otp/osm/`, tunnel token in `cloudflare/.env` if you want the public hostname.

```bash
./scripts/server/setup.sh
./scripts/server/up.sh --build -d
```

Windows: `.\scripts\server\setup.ps1` then `.\scripts\server\up.ps1 -Build -Detached`.

Public API (when the tunnel is up): `https://api.horiasavin.me`

**App** — from `frontend/`:

```bash
flutter run
```

Defaults to the public API. Emulator + local backend: `--dart-define=API_BASE_URL=http://10.0.2.2:8085`. Android Studio: open the `frontend` folder, JDK 21, see [`frontend/README.md`](frontend/README.md).

## Repo layout

| Path | What it is |
|------|------------|
| `frontend/` | Flutter app |
| `backend/` | Spring API |
| `otp/` | OpenTripPlanner graph inputs and config |
| `db/` | Postgres init + GTFS import notes |
| `docs/` | Technical spec |
| `scripts/` | Server, DB, and Android Studio helpers |
