# 1. Prerequisites
- Docker Desktop installed and running
- Enough RAM for OTP graph build (recomended: 4-8 GB free)
- GTFS feed zip and OSM .pbf file for your target area

# 2. Build and run with Docker Compose

From repo root:
```
docker compose up --build -d
```

What this does:
- builds the image from otp/Dockerfile
- starts OTP container
- runs OTP with --build --serve (graph build + API server)

# 3. Verify OTP is healthy
1. Check container statur:
```
docker compose ps
```
otp should be up (not restarting)
2. Check logs:
```
docker compose logs otp --tail=300
```

Look for successful startup (graph build done + server listening)

3. Test API:
```
Invoke-WebRequest http://localhost:8080/otp/routers/default -UseBasicParsing
```
Expected: HTTP 200

# 4. Stop/restart commands

- Stop:
```
docker compose down
```

- Restart:
```
docker compose restart otp
```