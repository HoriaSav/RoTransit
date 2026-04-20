-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;

--------------------------------------------------
-- USERS
--------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL,                     -- google, apple, guest
    provider_user_id TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    CONSTRAINT users_provider_unique UNIQUE (provider, provider_user_id)
);

--------------------------------------------------
-- CITIES
--------------------------------------------------
CREATE TABLE IF NOT EXISTS cities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    country TEXT NOT NULL,
    otp_base_url TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    CONSTRAINT cities_unique UNIQUE (name, country)
);

--------------------------------------------------
-- SAVED ROUTES
--------------------------------------------------
CREATE TABLE IF NOT EXISTS saved_routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    city_id UUID NOT NULL,
    label TEXT,
    route_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),

    CONSTRAINT fk_saved_routes_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_saved_routes_city
        FOREIGN KEY (city_id)
        REFERENCES cities(id)
        ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_saved_routes_user_city
    ON saved_routes(user_id, city_id);

CREATE INDEX IF NOT EXISTS idx_saved_routes_user_created
    ON saved_routes(user_id, created_at DESC);

--------------------------------------------------
-- FAVORITE STOPS
--------------------------------------------------
CREATE TABLE IF NOT EXISTS favorite_stops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    city_id UUID NOT NULL,
    stop_id TEXT NOT NULL,
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),

    CONSTRAINT fk_favorite_stops_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_favorite_stops_city
        FOREIGN KEY (city_id)
        REFERENCES cities(id)
        ON DELETE CASCADE,

    CONSTRAINT unique_favorite_stop
        UNIQUE (user_id, city_id, stop_id)
);

-- Index for quick lookup
CREATE INDEX IF NOT EXISTS idx_favorite_stops_user_city
    ON favorite_stops(user_id, city_id);

--------------------------------------------------
-- SEED DATA
--------------------------------------------------
-- Fixed UUIDs so app clients (and imports) can use stable cityId across fresh Docker volumes.
INSERT INTO cities (id, name, country, otp_base_url)
VALUES (
    '93715d42-5523-4195-8743-53b6819488c9'::uuid,
    'Brasov',
    'Romania',
    'http://otp:8080/otp'
)
ON CONFLICT (name, country) DO NOTHING;

INSERT INTO cities (id, name, country, otp_base_url)
VALUES (
    'a1b2c3d4-e5f6-4789-a012-3456789abcde'::uuid,
    'Bucharest',
    'Romania',
    'http://otp:8080/otp'
)
ON CONFLICT (name, country) DO NOTHING;

--------------------------------------------------
-- GTFS READ MODEL (for app catalog queries)
--------------------------------------------------
CREATE TABLE IF NOT EXISTS gtfs_stops (
    city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
    stop_id TEXT NOT NULL,
    stop_name TEXT NOT NULL,
    stop_lat DOUBLE PRECISION NOT NULL,
    stop_lon DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (city_id, stop_id)
);

CREATE TABLE IF NOT EXISTS gtfs_routes (
    city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
    route_id TEXT NOT NULL,
    route_short_name TEXT,
    route_long_name TEXT,
    route_type INTEGER NOT NULL DEFAULT 3,
    PRIMARY KEY (city_id, route_id)
);

CREATE TABLE IF NOT EXISTS gtfs_trips (
    city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
    trip_id TEXT NOT NULL,
    route_id TEXT NOT NULL,
    service_id TEXT,
    trip_headsign TEXT,
    direction_id TEXT,
    PRIMARY KEY (city_id, trip_id)
);

CREATE TABLE IF NOT EXISTS gtfs_stop_times (
    city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
    trip_id TEXT NOT NULL,
    stop_id TEXT NOT NULL,
    stop_sequence INTEGER NOT NULL,
    arrival_time TEXT,
    departure_time TEXT,
    PRIMARY KEY (city_id, trip_id, stop_sequence)
);

CREATE TABLE IF NOT EXISTS gtfs_calendar (
    city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
    service_id TEXT NOT NULL,
    monday SMALLINT NOT NULL DEFAULT 0,
    tuesday SMALLINT NOT NULL DEFAULT 0,
    wednesday SMALLINT NOT NULL DEFAULT 0,
    thursday SMALLINT NOT NULL DEFAULT 0,
    friday SMALLINT NOT NULL DEFAULT 0,
    saturday SMALLINT NOT NULL DEFAULT 0,
    sunday SMALLINT NOT NULL DEFAULT 0,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    PRIMARY KEY (city_id, service_id)
);

CREATE TABLE IF NOT EXISTS gtfs_calendar_dates (
    city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
    service_id TEXT NOT NULL,
    service_date TEXT NOT NULL,
    exception_type SMALLINT NOT NULL,
    PRIMARY KEY (city_id, service_id, service_date)
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_gtfs_trips_route'
    ) THEN
        ALTER TABLE gtfs_trips
            ADD CONSTRAINT fk_gtfs_trips_route
            FOREIGN KEY (city_id, route_id)
            REFERENCES gtfs_routes (city_id, route_id)
            ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_gtfs_stop_times_trip'
    ) THEN
        ALTER TABLE gtfs_stop_times
            ADD CONSTRAINT fk_gtfs_stop_times_trip
            FOREIGN KEY (city_id, trip_id)
            REFERENCES gtfs_trips (city_id, trip_id)
            ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_gtfs_stop_times_stop'
    ) THEN
        ALTER TABLE gtfs_stop_times
            ADD CONSTRAINT fk_gtfs_stop_times_stop
            FOREIGN KEY (city_id, stop_id)
            REFERENCES gtfs_stops (city_id, stop_id)
            ON DELETE CASCADE;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_gtfs_stops_city_name
    ON gtfs_stops (city_id, lower(stop_name));
CREATE INDEX IF NOT EXISTS idx_gtfs_routes_city
    ON gtfs_routes (city_id, route_id);
CREATE INDEX IF NOT EXISTS idx_gtfs_routes_city_type
    ON gtfs_routes (city_id, route_type, route_short_name);
CREATE INDEX IF NOT EXISTS idx_gtfs_trips_city_route
    ON gtfs_trips (city_id, route_id);
CREATE INDEX IF NOT EXISTS idx_gtfs_trips_city_route_direction
    ON gtfs_trips (city_id, route_id, direction_id, trip_id);
CREATE INDEX IF NOT EXISTS idx_gtfs_stop_times_city_stop
    ON gtfs_stop_times (city_id, stop_id, departure_time);
CREATE INDEX IF NOT EXISTS idx_gtfs_stop_times_city_trip_seq
    ON gtfs_stop_times (city_id, trip_id, stop_sequence);
CREATE INDEX IF NOT EXISTS idx_gtfs_calendar_city_service
    ON gtfs_calendar (city_id, service_id);
CREATE INDEX IF NOT EXISTS idx_gtfs_calendar_dates_city_date
    ON gtfs_calendar_dates (city_id, service_date, service_id);
