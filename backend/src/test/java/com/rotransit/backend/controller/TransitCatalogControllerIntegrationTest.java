package com.rotransit.backend.controller;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class TransitCatalogControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM gtfs_calendar_dates",
            "DELETE FROM gtfs_calendar",
            "DELETE FROM gtfs_stop_times",
            "DELETE FROM gtfs_trips",
            "DELETE FROM gtfs_routes",
            "DELETE FROM gtfs_stops",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('abababab-abab-abab-abab-abababababab', 'Brasov', 'Romania', 'http://otp:8080/otp')",
            "INSERT INTO gtfs_routes (city_id, route_id, route_short_name, route_long_name, route_type) VALUES ('abababab-abab-abab-abab-abababababab','ROUTE:1','6','Livada - Rulmentul',3)",
            "INSERT INTO gtfs_routes (city_id, route_id, route_short_name, route_long_name, route_type) VALUES ('abababab-abab-abab-abab-abababababab','ROUTE:2','T1','Tram test',0)"
    })
    void listBusesReturnsOnlyBusRoutes() throws Exception {
        mockMvc.perform(get("/api/buses")
                        .queryParam("cityId", "abababab-abab-abab-abab-abababababab"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].shortName").value("6"))
                .andExpect(jsonPath("$[0].mode").value("BUS"));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM gtfs_calendar_dates",
            "DELETE FROM gtfs_calendar",
            "DELETE FROM gtfs_stop_times",
            "DELETE FROM gtfs_trips",
            "DELETE FROM gtfs_routes",
            "DELETE FROM gtfs_stops",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd', 'Brasov', 'Romania', 'http://otp:8080/otp')",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd','STOP:1','First',45.61,25.60)",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd','STOP:2','Second',45.62,25.61)",
            "INSERT INTO gtfs_routes (city_id, route_id, route_short_name, route_long_name, route_type) VALUES ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd','ROUTE:1','1','Route 1',3)",
            "INSERT INTO gtfs_trips (city_id, trip_id, route_id, service_id, trip_headsign, direction_id) VALUES ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd','TRIP:1','ROUTE:1','WEEK','Center','0')",
            "INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time) VALUES ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd','TRIP:1','STOP:1',1,'08:00:00','08:00:00')",
            "INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time) VALUES ('cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd','TRIP:1','STOP:2',2,'08:05:00','08:05:00')"
    })
    void routeStopsReturnsOrderedStops() throws Exception {
        mockMvc.perform(get("/api/buses/ROUTE:1/stops")
                        .queryParam("cityId", "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd")
                        .queryParam("directionId", "0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].stopSequence").value(1))
                .andExpect(jsonPath("$[1].stopSequence").value(2));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM gtfs_calendar_dates",
            "DELETE FROM gtfs_calendar",
            "DELETE FROM gtfs_stop_times",
            "DELETE FROM gtfs_trips",
            "DELETE FROM gtfs_routes",
            "DELETE FROM gtfs_stops",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('dadadada-dada-dada-dada-dadadadadada', 'Brasov', 'Romania', 'http://otp:8080/otp')",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('dadadada-dada-dada-dada-dadadadadada','STOP:1','First',45.61,25.60)",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('dadadada-dada-dada-dada-dadadadadada','STOP:2','Second',45.62,25.61)",
            "INSERT INTO gtfs_routes (city_id, route_id, route_short_name, route_long_name, route_type) VALUES ('dadadada-dada-dada-dada-dadadadadada','ROUTE:100','100','Route 100',3)",
            "INSERT INTO gtfs_trips (city_id, trip_id, route_id, service_id, trip_headsign, direction_id) VALUES ('dadadada-dada-dada-dada-dadadadadada','TRIP:10','ROUTE:100','WEEK','Center','0')",
            "INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time) VALUES ('dadadada-dada-dada-dada-dadadadadada','TRIP:10','STOP:1',1,'08:00:00','08:00:00')",
            "INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time) VALUES ('dadadada-dada-dada-dada-dadadadadada','TRIP:10','STOP:2',2,'08:05:00','08:05:00')"
    })
    void routeStopsWorksWhenDirectionIsMissing() throws Exception {
        mockMvc.perform(get("/api/buses/ROUTE:100/stops")
                        .queryParam("cityId", "dadadada-dada-dada-dada-dadadadadada"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].stopSequence").value(1))
                .andExpect(jsonPath("$[1].stopSequence").value(2));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM gtfs_calendar_dates",
            "DELETE FROM gtfs_calendar",
            "DELETE FROM gtfs_stop_times",
            "DELETE FROM gtfs_trips",
            "DELETE FROM gtfs_routes",
            "DELETE FROM gtfs_stops",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('efefefef-efef-efef-efef-efefefefefef', 'Brasov', 'Romania', 'http://otp:8080/otp')",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('efefefef-efef-efef-efef-efefefefefef','STOP:1','First',45.61,25.60)",
            "INSERT INTO gtfs_routes (city_id, route_id, route_short_name, route_long_name, route_type) VALUES ('efefefef-efef-efef-efef-efefefefefef','ROUTE:1','1','Route 1',3)",
            "INSERT INTO gtfs_trips (city_id, trip_id, route_id, service_id, trip_headsign, direction_id) VALUES ('efefefef-efef-efef-efef-efefefefefef','TRIP:1','ROUTE:1','WEEK','Center','0')",
            "INSERT INTO gtfs_trips (city_id, trip_id, route_id, service_id, trip_headsign, direction_id) VALUES ('efefefef-efef-efef-efef-efefefefefef','TRIP:2','ROUTE:1','WEEK','Center','0')",
            "INSERT INTO gtfs_calendar (city_id, service_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date) VALUES ('efefefef-efef-efef-efef-efefefefefef','WEEK',1,1,1,1,1,0,0,'20260401','20260430')",
            "INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time) VALUES ('efefefef-efef-efef-efef-efefefefefef','TRIP:1','STOP:1',1,'08:10:00','08:10:00')",
            "INSERT INTO gtfs_stop_times (city_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time) VALUES ('efefefef-efef-efef-efef-efefefefefef','TRIP:2','STOP:1',1,'08:25:00','08:25:00')"
    })
    void routeTimetableReturnsDepartures() throws Exception {
        mockMvc.perform(get("/api/buses/ROUTE:1/timetable")
                        .queryParam("cityId", "efefefef-efef-efef-efef-efefefefefef")
                        .queryParam("stopId", "STOP:1")
                        .queryParam("serviceDate", "2026-04-01"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.departures.length()").value(2))
                .andExpect(jsonPath("$.departures[0].departureTime").value("08:10:00"));
    }
}
