package com.rotransit.backend.service;

import com.rotransit.backend.dto.BusLineResponse;
import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.dto.RouteStopResponse;
import com.rotransit.backend.dto.StopTimetableEntryResponse;
import jakarta.annotation.PostConstruct;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class GtfsReadService {

    private final JdbcTemplate jdbcTemplate;

    public GtfsReadService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @PostConstruct
    public void ensureSchema() {
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS gtfs_stops (
                    city_id UUID NOT NULL,
                    stop_id VARCHAR(255) NOT NULL,
                    stop_name VARCHAR(512) NOT NULL,
                    stop_lat DOUBLE PRECISION NOT NULL,
                    stop_lon DOUBLE PRECISION NOT NULL,
                    PRIMARY KEY (city_id, stop_id)
                )
                """);
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS gtfs_routes (
                    city_id UUID NOT NULL,
                    route_id VARCHAR(255) NOT NULL,
                    route_short_name VARCHAR(255),
                    route_long_name VARCHAR(512),
                    route_type INTEGER NOT NULL DEFAULT 3,
                    PRIMARY KEY (city_id, route_id)
                )
                """);
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS gtfs_trips (
                    city_id UUID NOT NULL,
                    trip_id VARCHAR(255) NOT NULL,
                    route_id VARCHAR(255) NOT NULL,
                    service_id VARCHAR(255),
                    trip_headsign VARCHAR(512),
                    direction_id VARCHAR(64),
                    PRIMARY KEY (city_id, trip_id)
                )
                """);
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS gtfs_stop_times (
                    city_id UUID NOT NULL,
                    trip_id VARCHAR(255) NOT NULL,
                    stop_id VARCHAR(255) NOT NULL,
                    stop_sequence INTEGER NOT NULL,
                    arrival_time VARCHAR(64),
                    departure_time VARCHAR(64),
                    PRIMARY KEY (city_id, trip_id, stop_sequence)
                )
                """);
        jdbcTemplate.execute("""
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
                )
                """);
        jdbcTemplate.execute("""
                CREATE TABLE IF NOT EXISTS gtfs_calendar_dates (
                    city_id UUID NOT NULL,
                    service_id VARCHAR(255) NOT NULL,
                    service_date VARCHAR(8) NOT NULL,
                    exception_type INTEGER NOT NULL,
                    PRIMARY KEY (city_id, service_id, service_date)
                )
                """);
    }

    public List<NearbyStopResponse> searchStops(UUID cityId, String query, int limit) {
        String sql = """
                SELECT stop_id, stop_name, stop_lat, stop_lon
                FROM gtfs_stops
                WHERE city_id = ? AND LOWER(stop_name) LIKE LOWER(?)
                ORDER BY
                  CASE WHEN LOWER(stop_name) LIKE LOWER(?) THEN 0 ELSE 1 END,
                  stop_name
                LIMIT ?
                """;
        String contains = "%" + query + "%";
        String prefix = query + "%";
        return jdbcTemplate.query(
                sql,
                (rs, rowNum) -> new NearbyStopResponse(
                        rs.getString("stop_id"),
                        rs.getString("stop_name"),
                        rs.getDouble("stop_lat"),
                        rs.getDouble("stop_lon")
                ),
                cityId,
                contains,
                prefix,
                limit
        );
    }

    public List<BusLineResponse> listBusLines(UUID cityId) {
        String sql = """
                SELECT route_id, COALESCE(route_short_name, '') AS route_short_name,
                       COALESCE(route_long_name, '') AS route_long_name, route_type
                FROM gtfs_routes
                WHERE city_id = ? AND route_type IN (3, 11, 700, 800)
                ORDER BY route_short_name, route_long_name
                """;
        return jdbcTemplate.query(
                sql,
                (rs, rowNum) -> new BusLineResponse(
                        rs.getString("route_id"),
                        rs.getString("route_short_name"),
                        rs.getString("route_long_name"),
                        mapRouteTypeToMode(rs.getInt("route_type"))
                ),
                cityId
        );
    }

    public List<RouteStopResponse> routeStops(UUID cityId, String routeId, String directionId) {
        String baseSelect = """
                SELECT DISTINCT ON (st.stop_sequence, s.stop_id)
                    s.stop_id, s.stop_name, s.stop_lat, s.stop_lon, st.stop_sequence
                FROM gtfs_stop_times st
                JOIN gtfs_trips t ON t.city_id = st.city_id AND t.trip_id = st.trip_id
                JOIN gtfs_stops s ON s.city_id = st.city_id AND s.stop_id = st.stop_id
                WHERE st.city_id = ? AND t.route_id = ?
                """;
        String orderBy = " ORDER BY st.stop_sequence ASC, s.stop_id";
        if (directionId == null || directionId.isBlank()) {
            return jdbcTemplate.query(
                    baseSelect + orderBy,
                    (rs, rowNum) -> new RouteStopResponse(
                            rs.getString("stop_id"),
                            rs.getString("stop_name"),
                            rs.getDouble("stop_lat"),
                            rs.getDouble("stop_lon"),
                            rs.getInt("stop_sequence")
                    ),
                    cityId,
                    routeId
            );
        }
        return jdbcTemplate.query(
                baseSelect + " AND t.direction_id = ?" + orderBy,
                (rs, rowNum) -> new RouteStopResponse(
                        rs.getString("stop_id"),
                        rs.getString("stop_name"),
                        rs.getDouble("stop_lat"),
                        rs.getDouble("stop_lon"),
                        rs.getInt("stop_sequence")
                ),
                cityId,
                routeId,
                directionId
        );
    }

    public List<StopTimetableEntryResponse> routeStopTimes(
            UUID cityId,
            String routeId,
            String stopId,
            LocalDate serviceDate,
            String directionId
    ) {
        String weekdayColumn = switch (serviceDate.getDayOfWeek()) {
            case MONDAY -> "monday";
            case TUESDAY -> "tuesday";
            case WEDNESDAY -> "wednesday";
            case THURSDAY -> "thursday";
            case FRIDAY -> "friday";
            case SATURDAY -> "saturday";
            case SUNDAY -> "sunday";
        };
        String serviceDateKey = serviceDate.format(DateTimeFormatter.BASIC_ISO_DATE);

        String sql = """
                SELECT st.trip_id, COALESCE(t.trip_headsign, '') AS trip_headsign, st.departure_time
                FROM gtfs_stop_times st
                JOIN gtfs_trips t ON t.city_id = st.city_id AND t.trip_id = st.trip_id
                WHERE st.city_id = ?
                  AND t.route_id = ?
                  AND st.stop_id = ?
                  AND st.departure_time IS NOT NULL
                  AND (? IS NULL OR ? = '' OR COALESCE(t.direction_id, '') = ?)
                  AND (
                    (
                      EXISTS (
                        SELECT 1
                        FROM gtfs_calendar c
                        WHERE c.city_id = t.city_id
                          AND c.service_id = t.service_id
                          AND c.%s = 1
                          AND c.start_date <= ?
                          AND c.end_date >= ?
                      )
                      AND NOT EXISTS (
                        SELECT 1
                        FROM gtfs_calendar_dates cd
                        WHERE cd.city_id = t.city_id
                          AND cd.service_id = t.service_id
                          AND cd.service_date = ?
                          AND cd.exception_type = 2
                      )
                    )
                    OR EXISTS (
                      SELECT 1
                      FROM gtfs_calendar_dates cd
                      WHERE cd.city_id = t.city_id
                        AND cd.service_id = t.service_id
                        AND cd.service_date = ?
                        AND cd.exception_type = 1
                    )
                  )
                ORDER BY st.departure_time ASC
                """.formatted(weekdayColumn);
        return jdbcTemplate.query(
                sql,
                (rs, rowNum) -> new StopTimetableEntryResponse(
                        rs.getString("trip_id"),
                        rs.getString("trip_headsign"),
                        rs.getString("departure_time")
                ),
                cityId,
                routeId,
                stopId,
                directionId,
                directionId,
                directionId,
                serviceDateKey,
                serviceDateKey,
                serviceDateKey,
                serviceDateKey
        );
    }

    private String mapRouteTypeToMode(int routeType) {
        return switch (routeType) {
            case 0 -> "TRAM";
            case 1 -> "SUBWAY";
            case 2 -> "RAIL";
            default -> "BUS";
        };
    }

    /**
     * All GTFS stops in the city whose normalized name equals {@code normalizedName}
     * (same rules as {@link StopSuggestionMerge#normalizeName(String)}).
     */
    public List<NearbyStopResponse> findStopsByNormalizedName(UUID cityId, String normalizedName) {
        if (normalizedName == null || normalizedName.isBlank()) {
            return List.of();
        }
        String likePattern = likePatternForNormalizedStopName(normalizedName);
        String sql = """
                SELECT stop_id, stop_name, stop_lat, stop_lon
                FROM gtfs_stops
                WHERE city_id = ?
                  AND LOWER(stop_name) LIKE ?
                """;
        List<NearbyStopResponse> rows = jdbcTemplate.query(
                sql,
                (rs, rowNum) -> new NearbyStopResponse(
                        rs.getString("stop_id"),
                        rs.getString("stop_name"),
                        rs.getDouble("stop_lat"),
                        rs.getDouble("stop_lon")
                ),
                cityId,
                likePattern.toLowerCase(Locale.ROOT));
        return rows.stream()
                .filter(r -> normalizedName.equals(StopSuggestionMerge.normalizeName(r.name())))
                .toList();
    }

    /**
     * Cheap SQL prefilter: tokens of the normalized name as substrings in order (e.g. {@code %piata%doina%}).
     * Exact match is still enforced in Java.
     */
    private static String likePatternForNormalizedStopName(String normalizedName) {
        String[] tokens = normalizedName.split(" ");
        StringBuilder sb = new StringBuilder("%");
        boolean first = true;
        for (String t : tokens) {
            if (t.isEmpty()) {
                continue;
            }
            if (!first) {
                sb.append('%');
            }
            sb.append(t);
            first = false;
        }
        sb.append('%');
        return sb.toString();
    }
}
