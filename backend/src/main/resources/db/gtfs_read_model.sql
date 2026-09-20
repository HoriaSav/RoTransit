-- GTFS read model (app catalog queries). Prod applies via db/postgres/init/001_init.sql.
-- Tests load this via spring.sql.init (application-test.yml). Keep in sync with Compose init.

CREATE TABLE IF NOT EXISTS gtfs_stops (
    city_id UUID NOT NULL,
    stop_id VARCHAR(255) NOT NULL,
    stop_name VARCHAR(512) NOT NULL,
    stop_lat DOUBLE PRECISION NOT NULL,
    stop_lon DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (city_id, stop_id)
);

CREATE TABLE IF NOT EXISTS gtfs_routes (
    city_id UUID NOT NULL,
    route_id VARCHAR(255) NOT NULL,
    route_short_name VARCHAR(255),
    route_long_name VARCHAR(512),
    route_type INTEGER NOT NULL DEFAULT 3,
    PRIMARY KEY (city_id, route_id)
);

CREATE TABLE IF NOT EXISTS gtfs_trips (
    city_id UUID NOT NULL,
    trip_id VARCHAR(255) NOT NULL,
    route_id VARCHAR(255) NOT NULL,
    service_id VARCHAR(255),
    trip_headsign VARCHAR(512),
    direction_id VARCHAR(64),
    PRIMARY KEY (city_id, trip_id)
);

CREATE TABLE IF NOT EXISTS gtfs_stop_times (
    city_id UUID NOT NULL,
    trip_id VARCHAR(255) NOT NULL,
    stop_id VARCHAR(255) NOT NULL,
    stop_sequence INTEGER NOT NULL,
    arrival_time VARCHAR(64),
    departure_time VARCHAR(64),
    PRIMARY KEY (city_id, trip_id, stop_sequence)
);

CREATE TABLE IF NOT EXISTS gtfs_calendar (
    city_id UUID NOT NULL,
    service_id VARCHAR(255) NOT NULL,
    monday INTEGER NOT NULL DEFAULT 0,
    tuesday INTEGER NOT NULL DEFAULT 0,
    wednesday INTEGER NOT NULL DEFAULT 0,
    thursday INTEGER NOT NULL DEFAULT 0,
    friday INTEGER NOT NULL DEFAULT 0,
    saturday INTEGER NOT NULL DEFAULT 0,
    sunday INTEGER NOT NULL DEFAULT 0,
    start_date VARCHAR(8) NOT NULL,
    end_date VARCHAR(8) NOT NULL,
    PRIMARY KEY (city_id, service_id)
);

CREATE TABLE IF NOT EXISTS gtfs_calendar_dates (
    city_id UUID NOT NULL,
    service_id VARCHAR(255) NOT NULL,
    service_date VARCHAR(8) NOT NULL,
    exception_type INTEGER NOT NULL,
    PRIMARY KEY (city_id, service_id, service_date)
);
