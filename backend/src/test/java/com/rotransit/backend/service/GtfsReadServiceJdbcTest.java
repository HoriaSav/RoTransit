package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@JdbcTest
@ActiveProfiles("test")
@Import(GtfsReadService.class)
class GtfsReadServiceJdbcTest {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private GtfsReadService gtfsReadService;

    @BeforeEach
    void setUp() {
        jdbcTemplate.execute("DELETE FROM gtfs_stop_times");
        jdbcTemplate.execute("DELETE FROM gtfs_trips");
        jdbcTemplate.execute("DELETE FROM gtfs_routes");
        jdbcTemplate.execute("DELETE FROM gtfs_stops");

        jdbcTemplate.execute("DELETE FROM gtfs_calendar_dates");
        jdbcTemplate.execute("DELETE FROM gtfs_calendar");
    }

    @Test
    void searchStopsOrdersPrefixMatchesFirst() {
        UUID cityId = UUID.randomUUID();
        jdbcTemplate.update(
                "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES (?, ?, ?, ?, ?)",
                cityId, "1", "Central Station", 45.0, 25.0
        );
        jdbcTemplate.update(
                "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES (?, ?, ?, ?, ?)",
                cityId, "2", "Old Central Park", 45.1, 25.1
        );
        jdbcTemplate.update(
                "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES (?, ?, ?, ?, ?)",
                cityId, "3", "Random Stop", 45.2, 25.2
        );

        var result = gtfsReadService.searchStops(cityId, "Cent", 10);

        assertEquals(2, result.size());
        assertEquals("Central Station", result.get(0).name());
        assertEquals("Old Central Park", result.get(1).name());
    }

    @Test
    void findStopsByNormalizedNameReturnsAllMatchingPlatforms() {
        UUID cityId = UUID.randomUUID();
        jdbcTemplate.update(
                "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES (?, ?, ?, ?, ?)",
                cityId, "1", "Doina", 45.0, 25.0
        );
        jdbcTemplate.update(
                "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES (?, ?, ?, ?, ?)",
                cityId, "2", "  DOINA ", 45.1, 25.1
        );
        jdbcTemplate.update(
                "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES (?, ?, ?, ?, ?)",
                cityId, "3", "Piata Doina", 45.2, 25.2
        );

        var out = gtfsReadService.findStopsByNormalizedName(cityId, "doina");

        assertEquals(2, out.size());
    }

    @Test
    void listBusLinesReturnsOnlyRouteType3AndMapsMode() {
        UUID cityId = UUID.randomUUID();
        jdbcTemplate.update(
                "INSERT INTO gtfs_routes (city_id, route_id, route_short_name, route_long_name, route_type) VALUES (?, ?, ?, ?, ?)",
                cityId, "bus-1", "1", "Bus One", 3
        );
        jdbcTemplate.update(
                "INSERT INTO gtfs_routes (city_id, route_id, route_short_name, route_long_name, route_type) VALUES (?, ?, ?, ?, ?)",
                cityId, "tram-1", "T1", "Tram One", 0
        );

        var result = gtfsReadService.listBusLines(cityId);

        assertEquals(1, result.size());
        assertEquals("bus-1", result.get(0).routeId());
        assertEquals("BUS", result.get(0).mode());
    }

    @Test
    void routeStopTimesRespectsCalendarWindowForWeekday() {
        UUID cityId = UUID.randomUUID();
        String serviceId = "weekday-service";
        String routeId = "R1";
        String tripId = "T1";
        String stopId = "S1";
        LocalDate mondayDate = LocalDate.of(2026, 4, 6);

        jdbcTemplate.update(
                "INSERT INTO gtfs_trips (city_id, trip_id, route_id, service_id, trip_headsign, direction_id) VALUES (?, ?, ?, ?, ?, ?)",
                cityId, tripId, routeId, serviceId, "Center", "0"
        );
        jdbcTemplate.update(
                "INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time) VALUES (?, ?, ?, ?, ?, ?)",
                cityId, tripId, stopId, 1, "08:00:00", "08:05:00"
        );
        jdbcTemplate.update(
                """
                INSERT INTO gtfs_calendar (
                    city_id, service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                cityId, serviceId, 1, 0, 0, 0, 0, 0, 0, "20260401", "20260430"
        );

        List<com.rotransit.backend.dto.StopTimetableEntryResponse> result =
                gtfsReadService.routeStopTimes(cityId, routeId, stopId, mondayDate, "0");

        assertEquals(1, result.size());
        assertEquals(tripId, result.get(0).tripId());
        assertEquals("08:05:00", result.get(0).departureTime());
    }

    @Test
    void routeStopTimesReturnsMoreThanOneHundredRowsWhenPresent() {
        UUID cityId = UUID.randomUUID();
        String serviceId = "weekday-service-many";
        String routeId = "R8";
        String stopId = "S8";
        LocalDate mondayDate = LocalDate.of(2026, 4, 6);

        jdbcTemplate.update(
                """
                INSERT INTO gtfs_calendar (
                    city_id, service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                cityId, serviceId, 1, 0, 0, 0, 0, 0, 0, "20260401", "20260430"
        );

        for (int i = 0; i < 108; i++) {
            String tripId = "T8-" + i;
            int hour = i / 4; // 4 departures per hour
            int minute = (i % 4) * 15;
            String hh = String.format("%02d", hour);
            String mm = String.format("%02d", minute);
            String dep = hh + ":" + mm + ":00";

            jdbcTemplate.update(
                    "INSERT INTO gtfs_trips (city_id, trip_id, route_id, service_id, trip_headsign, direction_id) VALUES (?, ?, ?, ?, ?, ?)",
                    cityId, tripId, routeId, serviceId, "Terminal", "0"
            );
            jdbcTemplate.update(
                    "INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time) VALUES (?, ?, ?, ?, ?, ?)",
                    cityId, tripId, stopId, 1, dep, dep
            );
        }

        List<com.rotransit.backend.dto.StopTimetableEntryResponse> result =
                gtfsReadService.routeStopTimes(cityId, routeId, stopId, mondayDate, "0");

        assertEquals(108, result.size());
        assertEquals("00:00:00", result.get(0).departureTime());
        assertEquals("26:45:00", result.get(107).departureTime());
    }
}
