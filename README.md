# RoTransit

## Quick start (full server + public domain)

**Prerequisites:** Docker, GTFS zip at `otp/gtfs/ro-ratbv.zip`, OSM `.pbf` under `otp/osm/`, Cloudflare tunnel token in `cloudflare/.env`.

```powershell
# Windows — one-time env files + checks
.\scripts\server\setup.ps1

# Windows — start everything (db, otp, backend, cloudflared tunnel)
.\scripts\server\up.ps1 -Build -Detached
```

```bash
# Linux — one-time
chmod +x scripts/server/setup.sh scripts/server/up.sh
./scripts/server/setup.sh

# Linux — start
./scripts/server/up.sh --build -d
```

**Public API:** `https://api.horiasavin.me`  
**Flutter (phone):** `flutter run --dart-define=API_BASE_URL=https://api.horiasavin.me`
