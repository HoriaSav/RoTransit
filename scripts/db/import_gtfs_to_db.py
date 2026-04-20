#!/usr/bin/env python3
"""
GTFS -> Postgres read-model importer (DB-owned).

Usage:
  python scripts/db/import_gtfs_to_db.py --gtfs "otp/gtfs/ro-ratbv.zip" --city-id <uuid>
  python scripts/db/import_gtfs_to_db.py --gtfs ... --city-name Brasov --country Romania --if-empty
"""
from __future__ import annotations

import argparse
import csv
import io
import os
import sys
import time
import zipfile
from typing import Iterable

import psycopg

REQUIRED_GTFS_FILES = ("stops.txt", "routes.txt", "trips.txt", "stop_times.txt")
OPTIONAL_GTFS_FILES = ("calendar.txt", "calendar_dates.txt")
REQUIRED_TABLES = (
    "cities",
    "gtfs_stops",
    "gtfs_routes",
    "gtfs_trips",
    "gtfs_stop_times",
    "gtfs_calendar",
    "gtfs_calendar_dates",
)


def read_csv_from_zip(zf: zipfile.ZipFile, filename: str) -> list[dict[str, str]]:
    with zf.open(filename) as handle:
        text = io.TextIOWrapper(handle, encoding="utf-8-sig")
        return list(csv.DictReader(text))


def upsert_many(cur: psycopg.Cursor, sql: str, rows: Iterable[tuple]) -> int:
    rows = list(rows)
    if not rows:
        return 0
    cur.executemany(sql, rows)
    return len(rows)


def ensure_city_exists(cur: psycopg.Cursor, city_id: str) -> None:
    cur.execute("SELECT 1 FROM cities WHERE id = %s", (city_id,))
    if cur.fetchone() is None:
        raise RuntimeError(
            f"City id {city_id} does not exist in cities table. "
            "Use /api/cities first and retry with a valid id."
        )


def resolve_city_id(
    cur: psycopg.Cursor,
    city_id: str | None,
    city_name: str | None,
    country: str,
) -> str:
    if city_id:
        ensure_city_exists(cur, city_id)
        return city_id
    if not city_name:
        raise RuntimeError("Internal error: neither city_id nor city_name set")
    cur.execute(
        "SELECT id FROM cities WHERE name = %s AND country = %s",
        (city_name, country),
    )
    rows = cur.fetchall()
    if len(rows) == 0:
        raise RuntimeError(
            f"No city named {city_name!r} with country {country!r} in cities table."
        )
    if len(rows) > 1:
        raise RuntimeError(
            f"Multiple cities named {city_name!r} in {country!r}; use --city-id instead."
        )
    return str(rows[0][0])


def ensure_tables_exist(cur: psycopg.Cursor) -> None:
    cur.execute(
        """
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
        """
    )
    existing = {row[0] for row in cur.fetchall()}
    missing = [table for table in REQUIRED_TABLES if table not in existing]
    if missing:
        raise RuntimeError(
            "Missing DB tables: "
            + ", ".join(missing)
            + ". Apply db/postgres/init/001_init.sql first."
        )


def ensure_required_files(zf: zipfile.ZipFile) -> None:
    members = set(zf.namelist())
    missing = [name for name in REQUIRED_GTFS_FILES if name not in members]
    if missing:
        raise RuntimeError("GTFS zip is missing required files: " + ", ".join(missing))


def maybe_read_csv(zf: zipfile.ZipFile, filename: str) -> list[dict[str, str]]:
    if filename not in set(zf.namelist()):
        return []
    return read_csv_from_zip(zf, filename)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gtfs", required=True, help="Path to GTFS zip file")
    cid = parser.add_mutually_exclusive_group(required=True)
    cid.add_argument("--city-id", help="City UUID from cities table")
    cid.add_argument("--city-name", help="City name (resolved with --country)")
    parser.add_argument(
        "--country",
        default="Romania",
        help="Country for --city-name (default: Romania)",
    )
    parser.add_argument(
        "--if-empty",
        action="store_true",
        help="Skip import if gtfs_routes already has rows for this city",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Import even when --if-empty would skip (also GTFS_IMPORT_FORCE=1)",
    )
    parser.add_argument(
        "--db-url",
        default=os.getenv("DB_URL", "postgresql://admin:rotransit_password@localhost:5433/rotransit"),
        help="Postgres URL in psycopg format",
    )
    args = parser.parse_args()

    force = args.force or os.getenv("GTFS_IMPORT_FORCE", "").lower() in (
        "1",
        "true",
        "yes",
    )
    if_empty = args.if_empty or os.getenv("GTFS_IMPORT_IF_EMPTY", "").lower() in (
        "1",
        "true",
        "yes",
    )

    started = time.time()

    with psycopg.connect(args.db_url) as conn:
        with conn.cursor() as cur:
            ensure_tables_exist(cur)
            city_id = resolve_city_id(
                cur, args.city_id, args.city_name, args.country
            )

            if if_empty and not force:
                cur.execute(
                    "SELECT COUNT(*) FROM gtfs_routes WHERE city_id = %s",
                    (city_id,),
                )
                n_existing = cur.fetchone()[0]
                if n_existing > 0:
                    print(
                        "GTFS import skipped: "
                        f"gtfs_routes already has {n_existing} row(s) for city_id={city_id} "
                        "(--if-empty). Use --force or unset GTFS_IMPORT_IF_EMPTY to reimport."
                    )
                    return 0

    if not os.path.isfile(args.gtfs):
        raise RuntimeError(f"GTFS zip not found at path: {args.gtfs}")

    with zipfile.ZipFile(args.gtfs) as zf:
        ensure_required_files(zf)
        stops = read_csv_from_zip(zf, "stops.txt")
        routes = read_csv_from_zip(zf, "routes.txt")
        trips = read_csv_from_zip(zf, "trips.txt")
        stop_times = read_csv_from_zip(zf, "stop_times.txt")
        calendar = maybe_read_csv(zf, "calendar.txt")
        calendar_dates = maybe_read_csv(zf, "calendar_dates.txt")

    with psycopg.connect(args.db_url) as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM gtfs_calendar_dates WHERE city_id = %s", (city_id,))
            cur.execute("DELETE FROM gtfs_calendar WHERE city_id = %s", (city_id,))
            cur.execute("DELETE FROM gtfs_stop_times WHERE city_id = %s", (city_id,))
            cur.execute("DELETE FROM gtfs_trips WHERE city_id = %s", (city_id,))
            cur.execute("DELETE FROM gtfs_routes WHERE city_id = %s", (city_id,))
            cur.execute("DELETE FROM gtfs_stops WHERE city_id = %s", (city_id,))

            n_stops = upsert_many(
                cur,
                """
                INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (city_id, stop_id) DO UPDATE
                SET stop_name = EXCLUDED.stop_name,
                    stop_lat = EXCLUDED.stop_lat,
                    stop_lon = EXCLUDED.stop_lon
                """,
                (
                    (
                        city_id,
                        row["stop_id"],
                        row.get("stop_name", ""),
                        float(row.get("stop_lat", 0) or 0),
                        float(row.get("stop_lon", 0) or 0),
                    )
                    for row in stops
                    if row.get("stop_id")
                ),
            )

            n_routes = upsert_many(
                cur,
                """
                INSERT INTO gtfs_routes (city_id, route_id, route_short_name, route_long_name, route_type)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (city_id, route_id) DO UPDATE
                SET route_short_name = EXCLUDED.route_short_name,
                    route_long_name = EXCLUDED.route_long_name,
                    route_type = EXCLUDED.route_type
                """,
                (
                    (
                        city_id,
                        row["route_id"],
                        row.get("route_short_name"),
                        row.get("route_long_name"),
                        int(row.get("route_type", 3) or 3),
                    )
                    for row in routes
                    if row.get("route_id")
                ),
            )

            n_trips = upsert_many(
                cur,
                """
                INSERT INTO gtfs_trips (city_id, trip_id, route_id, service_id, trip_headsign, direction_id)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (city_id, trip_id) DO UPDATE
                SET route_id = EXCLUDED.route_id,
                    service_id = EXCLUDED.service_id,
                    trip_headsign = EXCLUDED.trip_headsign,
                    direction_id = EXCLUDED.direction_id
                """,
                (
                    (
                        city_id,
                        row["trip_id"],
                        row.get("route_id"),
                        row.get("service_id"),
                        row.get("trip_headsign"),
                        row.get("direction_id"),
                    )
                    for row in trips
                    if row.get("trip_id") and row.get("route_id")
                ),
            )

            n_stop_times = upsert_many(
                cur,
                """
                INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (city_id, trip_id, stop_sequence) DO UPDATE
                SET stop_id = EXCLUDED.stop_id,
                    arrival_time = EXCLUDED.arrival_time,
                    departure_time = EXCLUDED.departure_time
                """,
                (
                    (
                        city_id,
                        row.get("trip_id"),
                        row.get("stop_id"),
                        int(row.get("stop_sequence", 0) or 0),
                        row.get("arrival_time"),
                        row.get("departure_time"),
                    )
                    for row in stop_times
                    if row.get("trip_id") and row.get("stop_id")
                ),
            )

            n_calendar = upsert_many(
                cur,
                """
                INSERT INTO gtfs_calendar (
                    city_id, service_id, monday, tuesday, wednesday, thursday,
                    friday, saturday, sunday, start_date, end_date
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (city_id, service_id) DO UPDATE
                SET monday = EXCLUDED.monday,
                    tuesday = EXCLUDED.tuesday,
                    wednesday = EXCLUDED.wednesday,
                    thursday = EXCLUDED.thursday,
                    friday = EXCLUDED.friday,
                    saturday = EXCLUDED.saturday,
                    sunday = EXCLUDED.sunday,
                    start_date = EXCLUDED.start_date,
                    end_date = EXCLUDED.end_date
                """,
                (
                    (
                        city_id,
                        row.get("service_id"),
                        int(row.get("monday", 0) or 0),
                        int(row.get("tuesday", 0) or 0),
                        int(row.get("wednesday", 0) or 0),
                        int(row.get("thursday", 0) or 0),
                        int(row.get("friday", 0) or 0),
                        int(row.get("saturday", 0) or 0),
                        int(row.get("sunday", 0) or 0),
                        row.get("start_date"),
                        row.get("end_date"),
                    )
                    for row in calendar
                    if row.get("service_id")
                ),
            )

            n_calendar_dates = upsert_many(
                cur,
                """
                INSERT INTO gtfs_calendar_dates (city_id, service_id, service_date, exception_type)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (city_id, service_id, service_date) DO UPDATE
                SET exception_type = EXCLUDED.exception_type
                """,
                (
                    (
                        city_id,
                        row.get("service_id"),
                        row.get("date"),
                        int(row.get("exception_type", 0) or 0),
                    )
                    for row in calendar_dates
                    if row.get("service_id") and row.get("date")
                ),
            )

    elapsed = time.time() - started
    print(
        "GTFS import complete "
        f"city={city_id} "
        f"stops={n_stops} routes={n_routes} trips={n_trips} stop_times={n_stop_times} "
        f"calendar={n_calendar} calendar_dates={n_calendar_dates} "
        f"elapsed_s={elapsed:.2f}"
    )
    missing_optional = [f for f in OPTIONAL_GTFS_FILES if (f == "calendar.txt" and n_calendar == 0) or (f == "calendar_dates.txt" and n_calendar_dates == 0)]
    if missing_optional:
        print(
            "Note: optional GTFS files were not loaded or had no rows: "
            + ", ".join(missing_optional)
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as ex:  # noqa: BLE001
        print(f"GTFS import failed: {ex}", file=sys.stderr)
        raise
