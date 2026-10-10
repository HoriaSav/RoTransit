# RoTransit

Public transport for Romanian cities, built on the official timetable data and kept on your phone.

[![Backend CI](https://github.com/HoriaSav/RoTransit/actions/workflows/backend.yml/badge.svg?branch=horia/spring-backend-rebuild)](https://github.com/HoriaSav/RoTransit/actions/workflows/backend.yml) [![Frontend CI](https://github.com/HoriaSav/RoTransit/actions/workflows/frontend.yml/badge.svg?branch=horia/spring-backend-rebuild)](https://github.com/HoriaSav/RoTransit/actions/workflows/frontend.yml)

## What it is

RoTransit is a mobile app for getting around Romanian cities by public transport. It uses the GTFS timetable data that transit operators publish, so stops, lines and departures come from the official schedules rather than from scraped or hand-typed data.

The backend has 13 cities seeded: Brasov, Bucuresti, Buzau, Cluj-Napoca, Constanta, Craiova, Iasi, Oradea, Ploiesti, Sibiu, Sinaia, Targoviste and Timisoara. The app itself currently works with Brasov (RATBV).

## Why use it

- **One app, official data.** Timetables come straight from the operators' GTFS feeds instead of a different website or PDF per city.
- **Works offline.** Stops, stop boards and line timetables are read from a local data pack on the phone, so they keep working without a connection. Map tiles may still need the network.
- **Private by design.** There's no account. Favourites and settings stay on the device.
- **Kept fresh in the background.** The server's only job is to keep each city's timetable current: it notices when a feed is about to expire, fetches the new one, and prepares timetables that start in the future so the switch happens on the right day.

## The app

<!-- Screenshots: drop these files into docs/screenshots/ (portrait phone captures):
     map.png, stop-board.png, timetable.png, favorites.png, settings.png, offline-pack.png -->

**Map with stop pins.** The map opens at street level around your location (it only asks for location when it can). Stop pins appear once you zoom in close enough, and you can also search stations by name.

**Stop boards.** Tap a stop to see its scheduled departures for the next while, with the option to show more. Times come from the timetable, not live GPS. Star the stop or open a line's timetable from there.

**Timetable.** Lines are grouped as Urban, Rural and TE (student transport, optional). Open a line, pick a stop and see its week timetable. If the bundled timetable data has run out, the app says so and asks you to update instead of showing wrong times.

**Favourites.** Your starred stops and lines in one place, saved on the phone.

**Settings and languages.** Pick your city, switch to dark mode, show or hide TE lines, see fares and where to buy tickets, and use the app in English, Romanian or German. Settings also shows the date the timetable data is from.

**Offline timetable pack.** Brașov's stops, lines and timetables ship inside the app as a local data pack, so boards and timetables work without a connection. New timetables arrive with app updates.

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/map.png" width="250" alt="Map"><br>Map</td>
    <td align="center"><img src="docs/screenshots/stop-board.png" width="250" alt="Stop board"><br>Stop board</td>
    <td align="center"><img src="docs/screenshots/timetable.png" width="250" alt="Timetable"><br>Timetable</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/favorites.png" width="250" alt="Favourites"><br>Favourites</td>
    <td align="center"><img src="docs/screenshots/settings.png" width="250" alt="Settings"><br>Settings</td>
    <td align="center"><img src="docs/screenshots/offline-pack.png" width="250" alt="Offline pack"><br>Offline pack</td>
  </tr>
</table>

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
