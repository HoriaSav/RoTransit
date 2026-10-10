#!/usr/bin/env python3
"""Build on-device Brașov companion SQLite from RATBV GTFS.

Output: frontend/assets/data/brasov_companion.sqlite.gz (the raw .sqlite is
deleted after compressing) plus a short manifest JSON next to it.

Does not require the RoTransit backend. Source GTFS is typically gitignored
under otp/gtfs/ro-ratbv.zip (ODbL / osm2gtfs unofficial RATBV feed).
"""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import os
import sqlite3
import zipfile
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo


CITY_ID = "93715d42-5523-4195-8743-53b6819488c9"
CITY_NAME = "Brașov"

ROUTE_TYPE_MODE = {
    "0": "TRAM",
    "1": "SUBWAY",
    "2": "RAIL",
    "3": "BUS",
    "11": "TROLLEYBUS",
}

# Bump when the layout changes; it is part of pack_version, so a schema-only
# change still makes installed apps re-extract the pack.
SCHEMA_VERSION = "3"

SCHEMA_SQL = """
        CREATE TABLE meta(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        CREATE TABLE stops(
          stop_id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          lat REAL NOT NULL,
          lon REAL NOT NULL
        );
        CREATE TABLE routes(
          route_id TEXT PRIMARY KEY,
          short_name TEXT NOT NULL,
          long_name TEXT NOT NULL,
          mode TEXT NOT NULL
        );
        CREATE TABLE route_stops(
          route_id TEXT NOT NULL,
          direction_id TEXT NOT NULL,
          stop_id TEXT NOT NULL,
          stop_sequence INTEGER NOT NULL,
          name TEXT NOT NULL,
          lat REAL NOT NULL,
          lon REAL NOT NULL,
          PRIMARY KEY(route_id, direction_id, stop_id)
        );
        CREATE TABLE departures(
          stop_id TEXT NOT NULL,
          route_id TEXT NOT NULL,
          direction_id TEXT NOT NULL,
          day_kind TEXT NOT NULL,
          service_id TEXT NOT NULL,
          trip_id TEXT NOT NULL,
          headsign TEXT NOT NULL,
          departure_time TEXT NOT NULL
        );
        CREATE INDEX idx_dep_stop_day ON departures(stop_id, day_kind, departure_time);
        CREATE INDEX idx_dep_route_stop ON departures(route_id, stop_id, direction_id, day_kind);
        CREATE TABLE trips(
          trip_id TEXT PRIMARY KEY,
          first_stop_name TEXT NOT NULL,
          last_stop_name TEXT NOT NULL
        );
        CREATE TABLE services(
          service_id TEXT PRIMARY KEY,
          monday INTEGER NOT NULL,
          tuesday INTEGER NOT NULL,
          wednesday INTEGER NOT NULL,
          thursday INTEGER NOT NULL,
          friday INTEGER NOT NULL,
          saturday INTEGER NOT NULL,
          sunday INTEGER NOT NULL,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL
        );
        CREATE TABLE service_exceptions(
          service_date TEXT NOT NULL,
          service_id TEXT NOT NULL,
          exception_type INTEGER NOT NULL,
          PRIMARY KEY(service_date, service_id)
        );
        CREATE TABLE day_overrides(
          service_date TEXT PRIMARY KEY,
          day_kind TEXT NOT NULL
        );
        """


def read_csv_from_zip(zf: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    with zf.open(name) as raw:
        text = raw.read().decode("utf-8-sig").splitlines()
    return list(csv.DictReader(text))


WEEKDAY_COLS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


def service_to_day_kinds(calendar_rows: list[dict[str, str]]) -> dict[str, set[str]]:
    """Day-type tabs (Mon-Fri / Sat / Sun) a service shows up in.

    Only for the Timetable week board. The stop board filters by the exact
    service calendar (services + service_exceptions tables).
    """
    out: dict[str, set[str]] = defaultdict(set)
    for row in calendar_rows:
        sid = row["service_id"]
        if row.get("saturday") == "1":
            out[sid].add("SATURDAY")
        if row.get("sunday") == "1":
            out[sid].add("SUNDAY")
        if any(row.get(d) == "1" for d in WEEKDAY_COLS[:5]):
            out[sid].add("MONFRI")
    return out


def iso_gtfs_date(raw: str) -> str:
    return parse_gtfs_date(raw).isoformat()


def parse_gtfs_date(raw: str) -> date:
    return date(int(raw[:4]), int(raw[4:6]), int(raw[6:8]))


def weekday_day_kind(d: date) -> str:
    if d.weekday() == 5:
        return "SATURDAY"
    if d.weekday() == 6:
        return "SUNDAY"
    return "MONFRI"


def day_kind_overrides(
    calendar_rows: list[dict[str, str]],
    calendar_dates: list[dict[str, str]],
    day_kinds_by_service: dict[str, set[str]],
) -> dict[str, str]:
    """Dates (YYYY-MM-DD) whose calendar_dates exceptions change the day kind.

    Example: a weekday public holiday that runs the Sunday services maps to
    SUNDAY. Only dates listed in calendar_dates.txt can differ from the weekday.
    """
    weekday_cols = WEEKDAY_COLS
    exceptions: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for row in calendar_dates:
        exceptions[row["date"]].append((row["service_id"], row["exception_type"]))

    out: dict[str, str] = {}
    for raw_date, changes in sorted(exceptions.items()):
        d = parse_gtfs_date(raw_date)
        active = {
            row["service_id"]
            for row in calendar_rows
            if row.get(weekday_cols[d.weekday()]) == "1"
            and row.get("start_date", "00000000") <= raw_date <= row.get("end_date", "99999999")
        }
        for sid, kind in changes:
            if kind == "1":
                active.add(sid)
            elif kind == "2":
                active.discard(sid)
        if not active:
            continue
        natural = weekday_day_kind(d)

        def score(kind: str) -> tuple[int, bool]:
            bucket = {sid for sid, kinds in day_kinds_by_service.items() if kind in kinds}
            return (len(active & bucket) - len(bucket - active), kind == natural)

        best = max(("MONFRI", "SATURDAY", "SUNDAY"), key=score)
        if best != natural:
            out[d.isoformat()] = best
    return out


def feed_data_as_of(feed_version: str, feed_start: str) -> str:
    """'Data as of' from feed_info: feed_version when it is a Unix timestamp
    (osm2gtfs export time, Bucharest date), else feed_start_date."""
    if feed_version.isdigit() and len(feed_version) >= 9:
        exported = datetime.fromtimestamp(int(feed_version), ZoneInfo("Europe/Bucharest"))
        return exported.date().isoformat()
    if len(feed_start) == 8 and feed_start.isdigit():
        return f"{feed_start[:4]}-{feed_start[4:6]}-{feed_start[6:]}"
    return date.today().isoformat()


def build(gtfs_zip: Path, out_db: Path, data_as_of: str | None = None) -> dict:
    out_db.parent.mkdir(parents=True, exist_ok=True)
    if out_db.exists():
        out_db.unlink()

    with zipfile.ZipFile(gtfs_zip) as zf:
        stops = read_csv_from_zip(zf, "stops.txt")
        routes = read_csv_from_zip(zf, "routes.txt")
        trips = read_csv_from_zip(zf, "trips.txt")
        calendar = read_csv_from_zip(zf, "calendar.txt")
        try:
            calendar_dates = read_csv_from_zip(zf, "calendar_dates.txt")
        except KeyError:
            calendar_dates = []
        try:
            feed_info = read_csv_from_zip(zf, "feed_info.txt")
        except KeyError:
            feed_info = []
        stop_times = read_csv_from_zip(zf, "stop_times.txt")

    day_kinds_by_service = service_to_day_kinds(calendar)
    overrides = day_kind_overrides(calendar, calendar_dates, day_kinds_by_service)
    feed_version = ""
    feed_start = ""
    feed_end = ""
    if feed_info:
        feed_version = feed_info[0].get("feed_version") or ""
        feed_start = feed_info[0].get("feed_start_date") or ""
        feed_end = feed_info[0].get("feed_end_date") or ""
    if not data_as_of:
        data_as_of = feed_data_as_of(feed_version, feed_start)

    # Anchor Monday from feed_start (or today).
    if feed_start and len(feed_start) == 8:
        start = date(int(feed_start[:4]), int(feed_start[4:6]), int(feed_start[6:8]))
    else:
        start = date.today()
    anchor = start - timedelta(days=start.weekday())

    trip_meta = {}
    for t in trips:
        trip_meta[t["trip_id"]] = {
            "route_id": t["route_id"],
            "service_id": t["service_id"],
            "direction_id": (t.get("direction_id") or "0").strip() or "0",
            "headsign": (t.get("trip_headsign") or "").strip(),
        }

    stop_by_id = {s["stop_id"]: s for s in stops}
    boardable = []
    for s in stops:
        lt = (s.get("location_type") or "0").strip() or "0"
        if lt not in ("0",):
            continue
        try:
            lat = float(s["stop_lat"])
            lon = float(s["stop_lon"])
        except (KeyError, ValueError, TypeError):
            continue
        if lat == 0 and lon == 0:
            continue
        boardable.append(
            {
                "stop_id": s["stop_id"],
                "name": (s.get("stop_name") or "").strip() or s["stop_id"],
                "lat": lat,
                "lon": lon,
            }
        )

    conn = sqlite3.connect(out_db)
    cur = conn.cursor()
    cur.execute("PRAGMA journal_mode=OFF")
    cur.executescript(SCHEMA_SQL)

    cur.executemany(
        "INSERT INTO stops(stop_id, name, lat, lon) VALUES(?,?,?,?)",
        [(s["stop_id"], s["name"], s["lat"], s["lon"]) for s in boardable],
    )

    route_rows = []
    for r in routes:
        mode = ROUTE_TYPE_MODE.get((r.get("route_type") or "3").strip(), "BUS")
        route_rows.append(
            (
                r["route_id"],
                (r.get("route_short_name") or r["route_id"]).strip(),
                (r.get("route_long_name") or "").strip(),
                mode,
            )
        )
    cur.executemany(
        "INSERT INTO routes(route_id, short_name, long_name, mode) VALUES(?,?,?,?)",
        route_rows,
    )

    # Collect ordered stops per (route, direction) from stop_times + trips.
    seq_map: dict[tuple[str, str, str], int] = {}
    for st in stop_times:
        tm = trip_meta.get(st["trip_id"])
        if not tm:
            continue
        key = (tm["route_id"], tm["direction_id"], st["stop_id"])
        seq = int(st.get("stop_sequence") or 0)
        prev = seq_map.get(key)
        if prev is None or seq < prev:
            seq_map[key] = seq

    route_stop_rows = []
    for (route_id, direction_id, stop_id), seq in seq_map.items():
        s = stop_by_id.get(stop_id)
        if not s:
            continue
        try:
            lat = float(s["stop_lat"])
            lon = float(s["stop_lon"])
        except (KeyError, ValueError, TypeError):
            continue
        name = (s.get("stop_name") or "").strip() or stop_id
        route_stop_rows.append((route_id, direction_id, stop_id, seq, name, lat, lon))
    cur.executemany(
        "INSERT OR REPLACE INTO route_stops(route_id, direction_id, stop_id, stop_sequence, name, lat, lon) VALUES(?,?,?,?,?,?,?)",
        route_stop_rows,
    )

    dep_rows = []
    for st in stop_times:
        tm = trip_meta.get(st["trip_id"])
        if not tm:
            continue
        # Services that only run on calendar_dates additions get no day-type
        # tab but still show on the stop board for their dates.
        kinds = day_kinds_by_service.get(tm["service_id"]) or {"DATES_ONLY"}
        dep = (st.get("departure_time") or st.get("arrival_time") or "").strip()
        if not dep:
            continue
        # Normalize HH:MM:SS (allow >24h)
        headsign = tm["headsign"] or (st.get("stop_headsign") or "").strip()
        for kind in kinds:
            dep_rows.append(
                (
                    st["stop_id"],
                    tm["route_id"],
                    tm["direction_id"],
                    kind,
                    tm["service_id"],
                    st["trip_id"],
                    headsign,
                    dep,
                )
            )

    cur.executemany(
        "INSERT INTO departures(stop_id, route_id, direction_id, day_kind, service_id, trip_id, headsign, departure_time) VALUES(?,?,?,?,?,?,?,?)",
        dep_rows,
    )
    # First and last stop of each trip, for "from -> to" on the stop board.
    trip_ends: dict[str, list] = {}
    for st in stop_times:
        if st["trip_id"] not in trip_meta:
            continue
        seq = int(st.get("stop_sequence") or 0)
        ends = trip_ends.setdefault(st["trip_id"], [seq, st["stop_id"], seq, st["stop_id"]])
        if seq < ends[0]:
            ends[0], ends[1] = seq, st["stop_id"]
        if seq > ends[2]:
            ends[2], ends[3] = seq, st["stop_id"]

    def stop_name(stop_id: str) -> str:
        s = stop_by_id.get(stop_id) or {}
        return (s.get("stop_name") or "").strip() or stop_id

    trip_rows = [
        (trip_id, stop_name(first), stop_name(last))
        for trip_id, (_, first, _, last) in trip_ends.items()
    ]
    cur.executemany(
        "INSERT INTO trips(trip_id, first_stop_name, last_stop_name) VALUES(?,?,?)",
        trip_rows,
    )
    cur.executemany(
        "INSERT INTO day_overrides(service_date, day_kind) VALUES(?,?)",
        sorted(overrides.items()),
    )
    service_rows = [
        (
            row["service_id"],
            *(1 if row.get(c) == "1" else 0 for c in WEEKDAY_COLS),
            iso_gtfs_date(row["start_date"]),
            iso_gtfs_date(row["end_date"]),
        )
        for row in calendar
    ]
    cur.executemany(
        "INSERT INTO services(service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date) VALUES(?,?,?,?,?,?,?,?,?,?)",
        service_rows,
    )
    exception_rows = [
        (iso_gtfs_date(row["date"]), row["service_id"], int(row["exception_type"]))
        for row in calendar_dates
    ]
    cur.executemany(
        "INSERT INTO service_exceptions(service_date, service_id, exception_type) VALUES(?,?,?)",
        exception_rows,
    )

    # Fingerprint of the actual content (not counts or dates), so changed
    # times produce a new pack_version and an unchanged feed keeps it.
    digest = hashlib.sha256(f"{CITY_ID}|{feed_version}|{SCHEMA_VERSION}|{SCHEMA_SQL}".encode())
    all_rows = (
        boardable_rows(boardable),
        route_rows,
        route_stop_rows,
        dep_rows,
        sorted(overrides.items()),
        service_rows,
        exception_rows,
        trip_rows,
    )
    for rows in all_rows:
        for row in sorted(rows):
            digest.update(repr(row).encode())
    pack_version = digest.hexdigest()
    generated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    meta = {
        "city_id": CITY_ID,
        "city_name": CITY_NAME,
        "anchor_monday": anchor.isoformat(),
        "data_as_of": data_as_of,
        "generated_at": generated_at,
        "pack_version": pack_version,
        "feed_version": feed_version,
        "feed_start_date": feed_start,
        "feed_end_date": feed_end,
        "source": "otp/gtfs/ro-ratbv.zip (RATBV via osm2gtfs / ODbL)",
        "schema_version": SCHEMA_VERSION,
    }
    cur.executemany(
        "INSERT INTO meta(key, value) VALUES(?, ?)",
        [(k, str(v)) for k, v in meta.items()],
    )

    conn.commit()
    # Vacuum for smaller asset
    cur.execute("VACUUM")
    conn.close()

    size = out_db.stat().st_size
    # The app bundles only the .gz; mtime=0 keeps the output reproducible.
    gz_path = out_db.with_name(out_db.name + ".gz")
    with open(out_db, "rb") as src, open(gz_path, "wb") as raw_out:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_out, mtime=0) as gz:
            gz.write(src.read())
    out_db.unlink()
    summary = {
        **meta,
        "stops": len(boardable),
        "routes": len(route_rows),
        "route_stop_rows": len(route_stop_rows),
        "departure_rows": len(dep_rows),
        "day_overrides": len(overrides),
        "trips": len(trip_rows),
        "services": len(service_rows),
        "service_exceptions": len(exception_rows),
        "db_bytes": size,
    }
    manifest = out_db.with_suffix(".manifest.json")
    manifest.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return summary


def boardable_rows(boardable: list[dict]) -> list[tuple]:
    return [(s["stop_id"], s["name"], s["lat"], s["lon"]) for s in boardable]


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--gtfs",
        type=Path,
        default=repo / "otp" / "gtfs" / "ro-ratbv.zip",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=repo / "frontend" / "assets" / "data" / "brasov_companion.sqlite",
    )
    parser.add_argument(
        "--data-as-of",
        default=None,
        help="Visible 'data as of' date (YYYY-MM-DD) for Settings; "
        "default: from the feed's feed_info (export time or start date)",
    )
    args = parser.parse_args()
    if not args.gtfs.is_file():
        raise SystemExit(f"GTFS zip not found: {args.gtfs}")
    build(args.gtfs, args.out, args.data_as_of)


if __name__ == "__main__":
    main()
