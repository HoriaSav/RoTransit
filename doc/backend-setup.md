# Backend Setup (Spring Boot)

## 1. Purpose
This document explains how to run the Spring Boot backend for RoTransit, what prerequisites are required, and how Maven Wrapper files (`mvnw`, `mvnw.cmd`) are used.

## 2. Prerequisites / Criteria
- Java 21 installed
- `JAVA_HOME` configured to the JDK root (example: `C:\Program Files\Java\jdk-21`)
- Docker Desktop running (for PostgreSQL container or full stack run)
- Backend folder contains:
  - `pom.xml`
  - `mvnw` and `mvnw.cmd`
  - `.mvn/wrapper/...`
- DB credentials are aligned between:
  - `db/postgres/.env`
  - `backend/.env` and/or `backend/src/main/resources/application.yml`

## 3. What are `mvnw` and `mvnw.cmd`?
- `mvnw` (Linux/macOS) and `mvnw.cmd` (Windows) are Maven Wrapper launchers.
- They ensure everyone uses the same Maven version defined in `.mvn/wrapper/maven-wrapper.properties`.
- Recommended usage in this project:
  - Windows: `.\mvnw.cmd <goal>`
  - Linux/macOS: `./mvnw <goal>`

## 4. Ports used in this project
- Backend API: `8085`
- PostgreSQL host port: `5433` (container internal port is `5432`)
- OTP: `8080`

## 5. Run backend with Docker (recommended first check)
From repo root:
```powershell
docker compose up -d db app
docker compose ps
```

Health check:
```text
http://localhost:8085/api/health
```
Expected response:
```json
{"status":"ok"}
```

## 6. Run backend locally (without app container)
1) Start DB only:
```powershell
cd D:\Licenta\RoTransit
docker compose up -d db
```

2) Stop app container if it is running (to avoid port conflicts):
```powershell
docker compose stop app
```

3) Start backend from `backend`:
```powershell
cd D:\Licenta\RoTransit\backend
.\mvnw.cmd spring-boot:run
```

4) Verify:
```text
http://localhost:8085/api/health
```

## 7. Common issues and fixes

### A) OTP host mismatch (`otp` vs `localhost`)
- If backend runs in Docker (`app` service), `cities.otp_base_url` should use Docker DNS:
  - `http://otp:8080/otp`
- If backend runs locally on host (`.\mvnw.cmd spring-boot:run`), `cities.otp_base_url` should use host URL:
  - `http://localhost:8080/otp`
- Quick SQL switch for local backend:
```powershell
docker compose exec db psql -U admin -d rotransit -c "update cities set otp_base_url='http://localhost:8080/otp';"
```

### B) `JAVA_HOME environment variable is not defined correctly`
- Set in terminal:
```powershell
$env:JAVA_HOME="C:\Program Files\Java\jdk-21"
$env:Path="$env:JAVA_HOME\bin;$env:Path"
```
- Verify: `mvn -v`

### C) `password authentication failed for user "rotransit_user"`
- Credentials mismatch or old DB volume.
- Reset DB volume and recreate:
```powershell
cd D:\Licenta\RoTransit
docker compose down -v
docker compose up -d db
```

### D) `Port ... already in use`
- Find process:
```powershell
netstat -ano | findstr :8085
tasklist /fi "PID eq <PID>"
```
- Or stop container using the same port:
```powershell
docker compose stop app
```

## 8. Useful commands
- Build backend jar:
```powershell
cd D:\Licenta\RoTransit\backend
.\mvnw.cmd clean package
```

- Follow backend logs (Docker):
```powershell
cd D:\Licenta\RoTransit
docker compose logs -f app
```

- Stop all services:
```powershell
docker compose down
```

- Run full local reliability gate:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/backend/run-local-gate.ps1
```
