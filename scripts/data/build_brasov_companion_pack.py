#!/usr/bin/env python3
"""Build on-device Brașov companion SQLite from RATBV GTFS.

Output: frontend/assets/data/brasov_companion.sqlite
Also writes a short manifest JSON next to it.

Does not require the RoTransit backend. Source GTFS is typically gitignored
under otp/gtfs/ro-ratbv.zip (ODbL / osm2gtfs unofficial RATBV feed).
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import sqlite3
import zipfile
from collections import defaultdict
from datetime import date, datetime, timezone
from pathlib import Path


CITY_ID = "93715d42-5523-4195-8743-53b6819488c9"
CITY_NAME = "Brașov"

ROUTE_TYPE_MODE = {
    "0": "TRAM",
    "1": "SUBWAY",
    "2": "RAIL",
    "3": "BUS",
    "11": "TROLLEYBUS",
}


def read_csv_from_zip(zf: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    with zf.open(name) as raw:
        text = raw.read().decode("utf-8-sig").splitlines()
    return list(csv.DictReader(text))


def service_to_day_kinds(calendar_rows: list[dict[str, str]]) -> dict[str, set[str]]:
    out: dict[str, set[str]] = defaultdict(set)
    for row in calendar_rows:
        sid = row["service_id"]
        if row.get("monday") == "1":
            out[sid].add("MONFRI")
        if row.get("saturday") == "1":
            out[sid].add("SATURDAY")
        if row.get("sunday") == "1":
            out[sid].add("SUNDAY")
        # Treat weekday-only blocks as MONFRI even if only some weekdays set.
        if any(row.get(d) == "1" for d in ("monday", "tuesday", "wednesday", "thursday", "friday")):
            out[sid].add("MONFRI")
    return out


def build(gtfs_zip: Path, out_db: Path, data_as_of: str) -> dict:
    out_db.parent.mkdir(parents=True, exist_ok=True)
    if out_db.exists():
        out_db.unlink()

    with zipfile.ZipFile(gtfs_zip) as zf:
        stops = read_csv_from_zip(zf, "stops.txt")
        routes = read_csv_from_zip(zf, "routes.txt")
        trips = read_csv_from_zip(zf, "trips.txt")
        calendar = read_csv_from_zip(zf, "calendar.txt")
        try:
            feed_info = read_csv_from_zip(zf, "feed_info.txt")
        except KeyError:
            feed_info = []
        stop_times = read_csv_from_zip(zf, "stop_times.txt")

    day_kinds_by_service = service_to_day_kinds(calendar)
    feed_version = ""
    feed_start = ""
    feed_end = ""
    if feed_info:
        feed_version = feed_info[0].get("feed_version") or ""
        feed_start = feed_info[0].get("feed_start_date") or ""
        feed_end = feed_info[0].get("feed_end_date") or ""

    # Anchor Monday from feed_start (or today).
    if feed_start and len(feed_start) == 8:
        start = date(int(feed_start[:4]), int(feed_start[4:6]), int(feed_start[6:8]))
    else:
        start = date.today()
    anchor = start - __import__("datetime").timedelta(days=start.weekday())

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
    cur.executescript(
        """
        PRAGMA journal_mode=OFF;
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
          trip_id TEXT NOT NULL,
          headsign TEXT NOT NULL,
          departure_time TEXT NOT NULL
        );
        CREATE INDEX idx_dep_stop_day ON departures(stop_id, day_kind, departure_time);
        CREATE INDEX idx_dep_route_stop ON departures(route_id, stop_id, direction_id, day_kind);
        """
    )

    pack_version_src = f"{CITY_ID}|{anchor.isoformat()}|{feed_version}|{len(boardable)}|{len(routes)}|{len(stop_times)}"
    pack_version = hashlib.sha256(pack_version_src.encode()).hexdigest()
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
        "schema_version": "1",
    }
    cur.executemany(
        "INSERT INTO meta(key, value) VALUES(?, ?)",
        [(k, str(v)) for k, v in meta.items()],
    )

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
        kinds = day_kinds_by_service.get(tm["service_id"]) or set()
        if not kinds:
            continue
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
                    st["trip_id"],
                    headsign,
                    dep,
                )
            )

    cur.executemany(
        "INSERT INTO departures(stop_id, route_id, direction_id, day_kind, trip_id, headsign, departure_time) VALUES(?,?,?,?,?,?,?)",
        dep_rows,
    )

    conn.commit()
    # Vacuum for smaller asset
    cur.execute("VACUUM")
    conn.close()

    size = out_db.stat().st_size
    summary = {
        **meta,
        "stops": len(boardable),
        "routes": len(route_rows),
        "route_stop_rows": len(route_stop_rows),
        "departure_rows": len(dep_rows),
        "db_bytes": size,
        "db_path": str(out_db),
    }
    manifest = out_db.with_suffix(".manifest.json")
    manifest.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    return summary


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
        default="2026-02-23",
        help="Visible 'data as of' date (YYYY-MM-DD) for Settings",
    )
    args = parser.parse_args()
    if not args.gtfs.is_file():
        raise SystemExit(f"GTFS zip not found: {args.gtfs}")
    build(args.gtfs, args.out, args.data_as_of)


if __name__ == "__main__":
    main()
