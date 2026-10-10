#!/usr/bin/env python3
"""Nightly health check of the GTFS feeds the backend serves.

Reads the feeds from the backend's seed migration (V2*.sql), downloads each one from the Mobility Database,
checks that it is a valid zip and how many days it has left, and writes a markdown table to the job summary.
Broken feeds and feeds expiring within 7 days are reported in one open GitHub issue labelled feed-health
(updated, not duplicated); when everything is healthy that issue is closed.

Standard library only. The issue part uses the gh CLI and runs only with GH_TOKEN set and without --dry-run;
otherwise it prints what it would do.
"""
import argparse
import csv
import io
import os
import re
import subprocess
import sys
import urllib.request
import zipfile
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "backend_v2/src/main/resources/db/migration"
URL = "https://files.mobilitydatabase.org/{id}/latest.zip"
TIMEOUT = 60  # seconds per download
WARN_DAYS = 7  # same rule as the backend's FeedUpdateJob: expiring = fewer than 7 days left
LABEL = "feed-health"
TITLE = "Feed health: broken or expiring GTFS feeds"
ZONE = ZoneInfo("Europe/Bucharest")


# ---- which feeds: parsed from the seed migration, so there is no second list to keep in sync ----

def rows(sql, table):
    """The value tuples of 'INSERT INTO table (...) VALUES (...), (...);' as lists of strings."""
    match = re.search(r"INSERT INTO\s+" + table + r"\s*\([^)]*\)\s*VALUES(.*?);", sql, re.S | re.I)
    if not match:
        sys.exit(f"no INSERT INTO {table} found in the seed migration")
    return [[v.strip().strip("'") for v in t.split(",")] for t in re.findall(r"\(([^)]*)\)", match.group(1))]


def feeds_from_seed():
    files = sorted(MIGRATIONS.glob("V2*.sql"))
    if not files:
        sys.exit(f"no V2*.sql in {MIGRATIONS}")
    sql = re.sub(r"--[^\n]*", "", files[0].read_text(encoding="utf-8"))  # drop comments first
    cities = {r[0]: r[1] for r in rows(sql, "city")}  # city id -> name
    feed_city = {r[0]: r[1] for r in rows(sql, "feed")}  # feed id -> city id
    feeds = []
    for feed_id, kind, ref, priority in rows(sql, "feed_source"):
        if kind == "mobilitydb" and priority == "1":
            feeds.append((cities[feed_city[feed_id]], ref))
    return feeds


# ---- reading the expiry date, like the backend: feed_info, then calendar, then calendar_dates ----

def csv_rows(archive, name):
    if name not in archive.namelist():
        return []
    # utf-8-sig drops a BOM; headers and values are trimmed because feeds often have stray spaces
    text = archive.read(name).decode("utf-8-sig")
    reader = csv.reader(io.StringIO(text))
    header = [h.strip() for h in next(reader, [])]
    return [dict(zip(header, (v.strip() for v in row))) for row in reader]


def latest(archive, name, column):
    dates = []
    for row in csv_rows(archive, name):
        try:
            dates.append(datetime.strptime(row.get(column, ""), "%Y%m%d").date())
        except ValueError:
            pass  # empty or malformed value: skip it, like the backend
    return max(dates, default=None)


def expiry(archive):
    return (latest(archive, "feed_info.txt", "feed_end_date")
            or latest(archive, "calendar.txt", "end_date")
            or latest(archive, "calendar_dates.txt", "date"))


def check(city, mdb_id, today):
    """One table row: (city, status, expires, days left, flagged)."""
    request = urllib.request.Request(URL.format(id=mdb_id), headers={"User-Agent": "RoTransit-feed-health"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            body = response.read()
        with zipfile.ZipFile(io.BytesIO(body)) as archive:
            if archive.testzip() is not None:
                raise zipfile.BadZipFile("a file in the zip is corrupt")
            expires = expiry(archive)
    except Exception as e:  # any failure (HTTP, timeout, bad zip, unreadable csv) means the feed is broken
        return city, f"broken: {type(e).__name__}: {e}", "-", "-", True
    if expires is None:
        return city, "no expiry date", "-", "-", True
    days = (expires - today).days
    if days < 0:
        status = "expired"
    elif days < WARN_DAYS:
        status = "expiring"
    else:
        status = "ok"
    return city, status, expires.isoformat(), str(days), status != "ok"


def table(results, today):
    lines = [f"### Feed health ({today.isoformat()}, Europe/Bucharest)", "",
             "| City | Status | Expires | Days left |", "|---|---|---|---:|"]
    for city, status, expires, days, flagged in results:
        mark = "⚠️ " if flagged else ""
        lines.append(f"| {city} | {mark}{status.replace('|', '/')} | {expires} | {days} |")
    return "\n".join(lines) + "\n"


# ---- the GitHub issue ----

def gh(*args, stdin=None, dry_run=False):
    if dry_run:
        print("[dry-run] would run: gh " + " ".join(args) + (" (body on stdin)" if stdin else ""))
        return ""
    done = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True)
    if done.returncode != 0:
        raise RuntimeError(f"gh {args[0]} {args[1]} failed: {done.stderr.strip()}")
    return done.stdout


def ensure_label(dry_run):
    if dry_run:
        gh("label", "create", LABEL, dry_run=True)
        return
    done = subprocess.run(["gh", "label", "create", LABEL, "--color", "d93f0b",
                           "--description", "Broken or expiring GTFS feeds"], capture_output=True, text=True)
    # "already exists" is fine; any other error is a real problem and must fail the run
    if done.returncode != 0 and "already exists" not in done.stderr:
        raise RuntimeError(f"gh label create failed: {done.stderr.strip()}")


def open_issues(dry_run):
    if dry_run:
        print(f"[dry-run] would look for open issues labelled {LABEL}")
        return []
    out = gh("issue", "list", "--label", LABEL, "--state", "open", "--json", "number", "--jq", ".[].number")
    return [n for n in out.split()]


def report(flagged, summary, dry_run):
    issues = open_issues(dry_run)
    if flagged:
        ensure_label(dry_run)
        body = f"{len(flagged)} feed(s) need attention.\n\n{summary}\n_Updated by the feed-health workflow._\n"
        if issues:
            # update the oldest open one instead of adding another
            gh("issue", "edit", sorted(issues, key=int)[0], "--body-file", "-", stdin=body, dry_run=dry_run)
        else:
            gh("issue", "create", "--title", TITLE, "--label", LABEL, "--body-file", "-", stdin=body,
               dry_run=dry_run)
        if dry_run:
            print("[dry-run] issue body:\n" + body)
    else:
        if dry_run:
            print("[dry-run] everything is healthy: would close any open feed-health issue with a comment")
        for number in issues:
            gh("issue", "close", number, "--comment", "All feeds are healthy again.", dry_run=dry_run)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="print the gh commands instead of running them")
    args = parser.parse_args()
    dry_run = args.dry_run or not os.environ.get("GH_TOKEN")

    today = datetime.now(ZONE).date()
    results = [check(city, mdb_id, today) for city, mdb_id in feeds_from_seed()]
    summary = table(results, today)

    summary_file = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_file:
        with open(summary_file, "a", encoding="utf-8") as f:
            f.write(summary)
    else:
        print(summary)

    flagged = [r for r in results if r[4]]
    report(flagged, summary, dry_run)


if __name__ == "__main__":
    main()
