package com.rotransit.backend.dto;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.LocalDate;
import java.time.LocalTime;
import org.junit.jupiter.api.Test;

class RouteSearchQueryTest {

    @Test
    void itineraryCountForPageClampsBetween8And40() {
        assertEquals(8, RouteSearchQuery.itineraryCountForPage(0, 1));
        assertEquals(8, RouteSearchQuery.itineraryCountForPage(-5, 0));
        assertEquals(20, RouteSearchQuery.itineraryCountForPage(0, 10));
        assertEquals(40, RouteSearchQuery.itineraryCountForPage(100, 50));
        assertEquals(40, RouteSearchQuery.itineraryCountForPage(0, 100));
    }

    @Test
    void forPagedSearchCopiesFieldsAndDerivesItineraryCount() {
        RouteSearchQuery q = RouteSearchQuery.forPagedSearch(
                "45.1,25.1",
                "45.2,25.2",
                LocalDate.of(2026, 9, 20),
                LocalTime.of(9, 15),
                2,
                5,
                10);

        assertEquals("45.1,25.1", q.origin());
        assertEquals("45.2,25.2", q.destination());
        assertEquals(LocalDate.of(2026, 9, 20), q.serviceDate());
        assertEquals(LocalTime.of(9, 15), q.serviceTime());
        assertEquals(2, q.passengerCount());
        assertEquals(RouteSearchQuery.itineraryCountForPage(5, 10), q.itineraryCount());
    }
}
