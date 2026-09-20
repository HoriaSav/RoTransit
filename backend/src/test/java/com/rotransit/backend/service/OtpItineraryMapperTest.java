package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.dto.LegPointResponse;
import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.RouteOptionResponse;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class OtpItineraryMapperTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private OtpItineraryMapper mapper;

    @BeforeEach
    void setUp() {
        mapper = new OtpItineraryMapper();
    }

    @Test
    void routesFromOtpPlanDefaultsMissingOptionalFields() throws Exception {
        JsonNode plan = objectMapper.readTree("""
                {"plan":{"itineraries":[{"legs":[{"from":{},"to":{}}]}]}}
                """);

        List<RouteOptionResponse> routes = mapper.routesFromOtpPlan(plan);

        assertEquals(1, routes.size());
        RouteOptionResponse route = routes.get(0);
        assertEquals(0L, route.durationSeconds());
        assertEquals(0, route.transfers());
        assertEquals(0L, route.walkDistanceMeters());
        assertEquals(0, route.estimatedPriceLei());
        assertEquals("5 lei / 90 min from first transit boarding", route.fareRule());
        assertEquals(1, route.legs().size());
        assertEquals("", route.legs().get(0).mode());
        assertEquals("", route.legs().get(0).routeId());
        assertEquals(0.0, route.legs().get(0).fromLat());
    }

    @Test
    void countTransfersFromLegsIgnoresAccessModes() throws Exception {
        JsonNode legs = objectMapper.readTree("""
                [
                  {"mode":"WALK"},
                  {"mode":"BUS"},
                  {"mode":"BICYCLE"},
                  {"mode":"TRAM"},
                  {"mode":"SCOOTER"}
                ]
                """);
        assertEquals(1, mapper.countTransfersFromLegs(legs));
        assertEquals(0, mapper.countTransfersFromLegs(objectMapper.readTree("[{\"mode\":\"BUS\"}]")));
        assertEquals(0, mapper.countTransfersFromLegs(objectMapper.readTree("{}")));
    }

    @Test
    void isTransitLegModeTreatsCarVariantsAsNonTransit() {
        assertFalse(mapper.isTransitLegMode("WALK"));
        assertFalse(mapper.isTransitLegMode("CAR_PARK"));
        assertFalse(mapper.isTransitLegMode("car_pickup"));
        assertTrue(mapper.isTransitLegMode("BUS"));
        assertTrue(mapper.isTransitLegMode("SUBWAY"));
        assertFalse(mapper.isTransitLegMode(""));
        assertFalse(mapper.isTransitLegMode(null));
    }

    @Test
    void estimatePriceLeiChargesFiveLeiPerNinetyMinuteWindow() throws Exception {
        long start = 1_000_000L;
        JsonNode under90 = objectMapper.readTree("""
                [{"mode":"BUS","startTime":%d,"endTime":%d}]
                """.formatted(start, start + 90L * 60L * 1000L - 1));
        JsonNode exact90 = objectMapper.readTree("""
                [{"mode":"BUS","startTime":%d,"endTime":%d}]
                """.formatted(start, start + 90L * 60L * 1000L));
        JsonNode over90 = objectMapper.readTree("""
                [{"mode":"WALK","startTime":0,"endTime":10},
                 {"mode":"BUS","startTime":%d,"endTime":%d}]
                """.formatted(start, start + 90L * 60L * 1000L + 1));

        assertEquals(5, mapper.estimatePriceLei(under90));
        assertEquals(5, mapper.estimatePriceLei(exact90));
        assertEquals(10, mapper.estimatePriceLei(over90));
        assertEquals(0, mapper.estimatePriceLei(objectMapper.readTree("[]")));
    }

    @Test
    void toGeometryPrefersLegGeometryThenGeometryPointsThenRawGeometry() throws Exception {
        String encoded = "_p~iF~ps|U";
        JsonNode viaLegGeometry = objectMapper.readTree("""
                {"legGeometry":{"points":"%s"}}
                """.formatted(encoded));
        JsonNode viaGeometryPoints = objectMapper.readTree("""
                {"geometry":{"points":"%s"}}
                """.formatted(encoded));
        JsonNode viaRawGeometry = objectMapper.readTree("""
                {"geometry":"%s"}
                """.formatted(encoded));

        List<LegPointResponse> a = mapper.toGeometry(viaLegGeometry);
        List<LegPointResponse> b = mapper.toGeometry(viaGeometryPoints);
        List<LegPointResponse> c = mapper.toGeometry(viaRawGeometry);

        assertEquals(1, a.size());
        assertEquals(a.get(0).lat(), b.get(0).lat(), 1e-5);
        assertEquals(a.get(0).lon(), c.get(0).lon(), 1e-5);
        assertTrue(mapper.toGeometry(objectMapper.readTree("{}")).isEmpty());
    }

    @Test
    void decodePolylineDecodesKnownEncoding() {
        List<LegPointResponse> points = mapper.decodePolyline("_p~iF~ps|U");
        assertEquals(1, points.size());
        assertEquals(38.5, points.get(0).lat(), 1e-4);
        assertEquals(-120.2, points.get(0).lon(), 1e-4);
    }

    @Test
    void toStopsFallsBackToFromAndToWhenIntermediateStopsMissing() throws Exception {
        JsonNode leg = objectMapper.readTree("""
                {
                  "from":{"name":"A","lat":1.0,"lon":2.0},
                  "to":{"name":"B","lat":3.0,"lon":4.0}
                }
                """);
        var stops = mapper.toStops(leg);
        assertEquals(2, stops.size());
        assertEquals("A", stops.get(0).name());
        assertEquals(1, stops.get(0).stopSequence());
        assertEquals("B", stops.get(1).name());
        assertEquals(2, stops.get(1).stopSequence());
    }

    @Test
    void toLegsReadsRouteGtfsIdWithRouteIdFallback() throws Exception {
        JsonNode legs = objectMapper.readTree("""
                [
                  {
                    "mode":"BUS",
                    "route":{"gtfsId":"agency:1"},
                    "from":{"name":"X","lat":1,"lon":2},
                    "to":{"name":"Y","lat":3,"lon":4},
                    "startTime":10,"endTime":20,"distance":100
                  },
                  {
                    "mode":"TRAM",
                    "routeId":"fallback-id",
                    "from":{"name":"Y","lat":3,"lon":4},
                    "to":{"name":"Z","lat":5,"lon":6},
                    "startTime":20,"endTime":30,"distance":200
                  }
                ]
                """);
        List<LegResponse> out = mapper.toLegs(legs);
        assertEquals("agency:1", out.get(0).routeId());
        assertEquals("fallback-id", out.get(1).routeId());
    }

    @Test
    void stripGeometryClearsPolylineButKeepsStopsAndFares() throws Exception {
        JsonNode plan = objectMapper.readTree("""
                {
                  "plan":{
                    "itineraries":[{
                      "duration":600,
                      "walkDistance":50,
                      "legs":[{
                        "mode":"BUS",
                        "route":{"gtfsId":"R1"},
                        "from":{"name":"A","lat":1,"lon":2},
                        "to":{"name":"B","lat":3,"lon":4},
                        "startTime":1000,"endTime":2000,"distance":500,
                        "legGeometry":{"points":"_p~iF~ps|U"},
                        "intermediateStops":[{"name":"Mid","lat":1.5,"lon":2.5,"stopSequence":2}]
                      }]
                    }]
                  }
                }
                """);
        RouteOptionResponse withGeom = mapper.routesFromOtpPlan(plan).get(0);
        assertFalse(withGeom.legs().get(0).geometry().isEmpty());
        assertEquals(1, withGeom.legs().get(0).stops().size());

        RouteOptionResponse stripped = mapper.stripGeometry(withGeom);
        assertTrue(stripped.legs().get(0).geometry().isEmpty());
        assertEquals(1, stripped.legs().get(0).stops().size());
        assertEquals(withGeom.estimatedPriceLei(), stripped.estimatedPriceLei());
        assertEquals(withGeom.fareRule(), stripped.fareRule());
        assertEquals(withGeom.durationSeconds(), stripped.durationSeconds());
    }
}
