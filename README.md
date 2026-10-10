# RoTransit

Public transport for Romanian cities, built on the official timetable data and kept on your phone.

[![Backend CI](https://github.com/HoriaSav/RoTransit/actions/workflows/backend.yml/badge.svg?branch=horia/spring-backend-rebuild)](https://github.com/HoriaSav/RoTransit/actions/workflows/backend.yml)

## What it is

RoTransit is a mobile app for getting around Romanian cities by public transport. It uses the GTFS timetable data that transit operators publish, so stops, lines and departures come from the official schedules rather than from scraped or hand-typed data.

The backend has 13 cities seeded: Brasov, Bucuresti, Buzau, Cluj-Napoca, Constanta, Craiova, Iasi, Oradea, Ploiesti, Sibiu, Sinaia, Targoviste and Timisoara. The app itself currently works with Brasov (RATBV).

## Why use it

- **One app, official data.** Timetables come straight from the operators' GTFS feeds instead of a different website or PDF per city.
- **Works offline.** Stops, stop boards and line timetables are read from a local data pack on the phone, so they keep working without a connection. Map tiles may still need the network.
- **Private by design.** There's no account. Favourites and settings stay on the device.
- **Kept fresh in the background.** The server's only job is to keep each city's timetable current: it notices when a feed is about to expire, fetches the new one, and prepares timetables that start in the future so the switch happens on the right day.

What the app does today:

| Feature | What you get |
|---------|--------------|
| Map | Stops on a map; tap one to see its departure board |
| Timetable | Browse lines and their timetables |
| Favourites | Save lines and journeys on the device |
| Settings | Language: English, Romanian or German |

## How it's built

A Flutter app does the work on the device: it reads the timetable data locally and shows maps, boards and timetables. A small Spring Boot service downloads each city's GTFS feed from the Mobility Database, tracks versions and expiry dates, and serves the zip files with a simple change check so the app only downloads when something is new.

| Component | What it is |
|-----------|------------|
| [`frontend/`](frontend/) | Flutter app for Android and iOS |
| [`backend_v2/`](backend_v2/) | Spring Boot feed service (Java 21, PostgreSQL). See its [README](backend_v2/README.md) |
| `backend/`, `otp/`, `cloudflare/` | The first version: a full server stack with OpenTripPlanner routing. Kept for reference |

## Status

RoTransit is in development. The backend is being rebuilt on the `horia/spring-backend-rebuild` branch, and the app doesn't use the new backend yet. Nothing is deployed or published in an app store yet.

## Quick start

To run the backend locally, follow [backend_v2/README.md](backend_v2/README.md#run-locally). For the app, see [frontend/README.md](frontend/README.md).

## Data

Timetable data is GTFS published by the transit operators of each city and collected by the [Mobility Database](https://mobilitydatabase.org). Credit for the schedules goes to them.
