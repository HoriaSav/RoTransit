package com.rotransit.backend.otp;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.rotransit.backend.service.RouteSearchQuery;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

@Component
public class OtpHttpClient implements OtpClient {

    /** Prefer transit over long walks; OTP may return no path if only a >1 km walk exists. */
    private static final int STRICT_MAX_WALK_METERS = 1000;
    private static final double STRICT_WALK_RELUCTANCE = 5.0;
    private static final double STRICT_WAIT_RELUCTANCE = 0.85;

    private final RestTemplate otpRestTemplate;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public OtpHttpClient(RestTemplate otpRestTemplate) {
        this.otpRestTemplate = otpRestTemplate;
    }

    @Override
    public JsonNode searchRoutes(String otpBaseUrl, RouteSearchQuery query) {
        JsonNode strictRest = searchRoutesRest(otpBaseUrl, query, true);
        if (planHasItineraries(strictRest)) {
            return strictRest;
        }
        JsonNode relaxedRest = searchRoutesRest(otpBaseUrl, query, false);
        if (planHasItineraries(relaxedRest)) {
            return relaxedRest;
        }
        // OTP 2.9+ fallback: GraphQL gtfs API (uses router-config defaults)
        try {
            JsonNode graphQlPlan = graphQlPlanSearch(otpBaseUrl, query);
            if (graphQlPlan != null && planHasItineraries(graphQlPlan)) {
                return graphQlPlan;
            }
        } catch (OtpException ignored) {
            // fall through to empty plan or last REST body
        }

        // Prefer any non-empty REST body from relaxed pass for debugging; else empty plan.
        if (relaxedRest != null && !relaxedRest.path("plan").isMissingNode()) {
            return relaxedRest;
        }
        if (strictRest != null && !strictRest.path("plan").isMissingNode()) {
            return strictRest;
        }
        ObjectNode empty = objectMapper.createObjectNode();
        empty.set("plan", objectMapper.createObjectNode().set("itineraries", objectMapper.createArrayNode()));
        return empty;
    }

    private JsonNode searchRoutesRest(String otpBaseUrl, RouteSearchQuery query, boolean strictWalk) {
        Set<String> baseCandidates = baseCandidates(otpBaseUrl);
        List<String> pathCandidates = List.of("/plan", "/routers/default/plan", "/otp/plan", "/otp/routers/default/plan");
        JsonNode lastBody = null;
        for (String base : baseCandidates) {
            for (String path : pathCandidates) {
                UriComponentsBuilder builder = UriComponentsBuilder.fromHttpUrl(base + path)
                        .queryParam("fromPlace", query.origin())
                        .queryParam("toPlace", query.destination())
                        .queryParam("numItineraries", query.itineraryCount())
                        .queryParam("date", query.serviceDate())
                        .queryParam("time", query.serviceTime())
                        .queryParam("locale", "en");
                if (strictWalk) {
                    builder.queryParam("maxWalkDistance", STRICT_MAX_WALK_METERS);
                    builder.queryParam("walkReluctance", STRICT_WALK_RELUCTANCE);
                    builder.queryParam("waitReluctance", STRICT_WAIT_RELUCTANCE);
                }
                String url = builder.toUriString();
                try {
                    JsonNode body = getJson(url);
                    lastBody = body;
                    if (planHasItineraries(body)) {
                        return body;
                    }
                } catch (OtpException ignored) {
                    // try next endpoint
                }
            }
        }
        return lastBody;
    }

    private static boolean planHasItineraries(JsonNode root) {
        if (root == null || root.isNull()) {
            return false;
        }
        JsonNode itineraries = root.path("plan").path("itineraries");
        return itineraries.isArray() && itineraries.size() > 0;
    }

    @Override
    public List<JsonNode> findNearbyStops(String otpBaseUrl, double latitude, double longitude, int radiusMeters) {
        List<String> pathCandidates = List.of("/routers/default/index/stops", "/otp/routers/default/index/stops");
        JsonNode body;
        try {
            body = getJsonWithCandidates(
                    otpBaseUrl,
                    pathCandidates,
                    List.of(
                            new QueryParam("lat", latitude),
                            new QueryParam("lon", longitude),
                            new QueryParam("radius", radiusMeters)
                    )
            );
        } catch (OtpException ex) {
            JsonNode graphQlStops = graphQlNearbyStops(otpBaseUrl, latitude, longitude, radiusMeters);
            if (graphQlStops != null && graphQlStops.isArray()) {
                List<JsonNode> result = new java.util.ArrayList<>();
                for (JsonNode stop : graphQlStops) {
                    result.add(stop);
                }
                return result;
            }
            return List.of();
        }
        if (body == null || !body.isArray()) {
            return List.of();
        }
        List<JsonNode> result = new java.util.ArrayList<>();
        for (JsonNode stop : body) {
            result.add(stop);
        }
        return result;
    }

    @Override
    public List<JsonNode> searchStops(String otpBaseUrl, String query, int limit) {
        List<String> basePathCandidates = List.of("/routers/default/index/stops", "/otp/routers/default/index/stops");
        List<List<QueryParam>> queryShapes = List.of(
                List.of(new QueryParam("query", query), new QueryParam("detail", "true")),
                List.of(new QueryParam("q", query), new QueryParam("detail", "true")),
                List.of(new QueryParam("detail", "true"))
        );

        for (List<QueryParam> queryParams : queryShapes) {
            try {
                JsonNode body = getJsonWithCandidates(otpBaseUrl, basePathCandidates, queryParams);
                if (body == null || !body.isArray()) {
                    continue;
                }
                List<JsonNode> result = new java.util.ArrayList<>();
                for (JsonNode stop : body) {
                    result.add(stop);
                }
                return result;
            } catch (OtpException ignored) {
                // Try next known OTP stops query shape.
            }
        }
        return List.of();
    }

    @Override
    public List<JsonNode> listBusRoutes(String otpBaseUrl) {
        return getArrayWithCandidates(
                otpBaseUrl,
                List.of("/routers/default/index/routes", "/otp/routers/default/index/routes"),
                List.of()
        );
    }

    @Override
    public List<JsonNode> listRouteStops(String otpBaseUrl, String routeId, String directionId) {
        List<QueryParam> queryParams = new java.util.ArrayList<>();
        if (directionId != null && !directionId.isBlank()) {
            queryParams.add(new QueryParam("direction", directionId));
        }
        return getArrayWithCandidates(
                otpBaseUrl,
                List.of(
                        "/routers/default/index/routes/" + routeId + "/stops",
                        "/otp/routers/default/index/routes/" + routeId + "/stops"
                ),
                queryParams
        );
    }

    @Override
    public List<JsonNode> routeStopTimes(String otpBaseUrl, String routeId, String stopId, String serviceDate) {
        return getArrayWithCandidates(
                otpBaseUrl,
                List.of(
                        "/routers/default/index/stops/" + stopId + "/stoptimes",
                        "/otp/routers/default/index/stops/" + stopId + "/stoptimes"
                ),
                List.of(
                        new QueryParam("startDate", serviceDate),
                        new QueryParam("endDate", serviceDate),
                        new QueryParam("routeId", routeId)
                )
        );
    }

    private List<JsonNode> getArray(String url) {
        JsonNode body = getJson(url);
        if (body == null || !body.isArray()) {
            return List.of();
        }
        List<JsonNode> result = new java.util.ArrayList<>();
        for (JsonNode item : body) {
            result.add(item);
        }
        return result;
    }

    private List<JsonNode> getArrayWithCandidates(String otpBaseUrl, List<String> pathCandidates, List<QueryParam> queryParams) {
        JsonNode body = getJsonWithCandidates(otpBaseUrl, pathCandidates, queryParams);
        if (body == null || !body.isArray()) {
            return List.of();
        }
        List<JsonNode> result = new java.util.ArrayList<>();
        for (JsonNode item : body) {
            result.add(item);
        }
        return result;
    }

    private JsonNode getJsonWithCandidates(String otpBaseUrl, List<String> pathCandidates, List<QueryParam> queryParams) {
        OtpException lastError = null;
        for (String base : baseCandidates(otpBaseUrl)) {
            for (String path : pathCandidates) {
                UriComponentsBuilder builder = UriComponentsBuilder.fromHttpUrl(base + path);
                for (QueryParam queryParam : queryParams) {
                    builder.queryParam(queryParam.key(), queryParam.value());
                }
                try {
                    return getJson(builder.toUriString());
                } catch (OtpException ex) {
                    lastError = ex;
                }
            }
        }
        if (lastError != null) {
            throw lastError;
        }
        throw new OtpException("OTP request failed with no candidate endpoints tried", null);
    }

    private Set<String> baseCandidates(String otpBaseUrl) {
        String normalizedBase = otpBaseUrl.endsWith("/")
                ? otpBaseUrl.substring(0, otpBaseUrl.length() - 1)
                : otpBaseUrl;
        Set<String> baseCandidates = new LinkedHashSet<>();
        baseCandidates.add(normalizedBase);
        if (normalizedBase.endsWith("/otp")) {
            baseCandidates.add(normalizedBase.substring(0, normalizedBase.length() - 4));
        } else {
            baseCandidates.add(normalizedBase + "/otp");
        }
        return baseCandidates;
    }

    private record QueryParam(String key, Object value) {
    }

    private JsonNode graphQlPlanSearch(String otpBaseUrl, RouteSearchQuery query) {
        String detailedQuery = """
                query Plan($fromLat: Float!, $fromLon: Float!, $toLat: Float!, $toLon: Float!, $date: String!, $time: String!, $num: Int!) {
                  plan(
                    from: {lat: $fromLat, lon: $fromLon}
                    to: {lat: $toLat, lon: $toLon}
                    date: $date
                    time: $time
                    numItineraries: $num
                  ) {
                    itineraries {
                      duration
                      walkDistance
                      legs {
                        mode
                        route {
                          gtfsId
                        }
                        distance
                        startTime
                        endTime
                        from {
                          name
                          lat
                          lon
                        }
                        to {
                          name
                          lat
                          lon
                        }
                        legGeometry {
                          points
                        }
                        intermediateStops {
                          name
                          lat
                          lon
                        }
                      }
                    }
                  }
                }
                """;
        String basicQuery = """
                query Plan($fromLat: Float!, $fromLon: Float!, $toLat: Float!, $toLon: Float!, $date: String!, $time: String!, $num: Int!) {
                  plan(
                    from: {lat: $fromLat, lon: $fromLon}
                    to: {lat: $toLat, lon: $toLon}
                    date: $date
                    time: $time
                    numItineraries: $num
                  ) {
                    itineraries {
                      duration
                      walkDistance
                      legs {
                        mode
                        distance
                        startTime
                        endTime
                        from {
                          name
                          lat
                          lon
                        }
                        to {
                          name
                          lat
                          lon
                        }
                      }
                    }
                  }
                }
                """;

        double[] from = parseLatLon(query.origin());
        double[] to = parseLatLon(query.destination());
        ObjectNode variables = objectMapper.createObjectNode();
        variables.put("fromLat", from[0]);
        variables.put("fromLon", from[1]);
        variables.put("toLat", to[0]);
        variables.put("toLon", to[1]);
        variables.put("date", query.serviceDate().toString());
        variables.put("time", query.serviceTime().toString());
        variables.put("num", query.itineraryCount());

        JsonNode response = postGraphQl(otpBaseUrl, detailedQuery, variables);
        JsonNode dataPlan = response.path("data").path("plan");
        boolean noDetailedItineraries = !dataPlan.path("itineraries").isArray()
                || dataPlan.path("itineraries").isEmpty();
        if (dataPlan.isMissingNode() || dataPlan.isNull() || noDetailedItineraries) {
            response = postGraphQl(otpBaseUrl, basicQuery, variables);
            dataPlan = response.path("data").path("plan");
        }
        if (dataPlan.isMissingNode() || dataPlan.isNull()) {
            throw new OtpException("OTP GraphQL plan query returned no plan payload", null);
        }

        ObjectNode wrapped = objectMapper.createObjectNode();
        wrapped.set("plan", dataPlan);
        return wrapped;
    }

    private JsonNode graphQlNearbyStops(String otpBaseUrl, double latitude, double longitude, int radiusMeters) {
        String graphQlQuery = """
                query StopsByRadius($lat: Float!, $lon: Float!, $radius: Int!) {
                  stopsByRadius(lat: $lat, lon: $lon, radius: $radius) {
                    edges {
                      node {
                        stop {
                          gtfsId
                          name
                          lat
                          lon
                        }
                      }
                    }
                  }
                }
                """;

        ObjectNode variables = objectMapper.createObjectNode();
        variables.put("lat", latitude);
        variables.put("lon", longitude);
        variables.put("radius", radiusMeters);

        JsonNode response = postGraphQl(otpBaseUrl, graphQlQuery, variables);
        JsonNode edges = response.path("data").path("stopsByRadius").path("edges");
        if (!edges.isArray()) {
            return objectMapper.createArrayNode();
        }
        ArrayNode out = objectMapper.createArrayNode();
        for (JsonNode edge : edges) {
            JsonNode stop = edge.path("node").path("stop");
            if (stop.isMissingNode() || stop.isNull()) {
                continue;
            }
            ObjectNode normalized = objectMapper.createObjectNode();
            normalized.put("id", stop.path("gtfsId").asText(""));
            normalized.put("name", stop.path("name").asText(""));
            normalized.put("lat", stop.path("lat").asDouble(0.0));
            normalized.put("lon", stop.path("lon").asDouble(0.0));
            out.add(normalized);
        }
        return out;
    }

    private JsonNode postGraphQl(String otpBaseUrl, String query, JsonNode variables) {
        OtpException lastError = null;
        for (String base : baseCandidates(otpBaseUrl)) {
            for (String path : List.of("/gtfs/v1", "/otp/gtfs/v1", "/transmodel/v3", "/otp/transmodel/v3")) {
                String url = base + path;
                ObjectNode body = objectMapper.createObjectNode();
                body.put("query", query);
                body.set("variables", variables);
                try {
                    ResponseEntity<JsonNode> response = otpRestTemplate.postForEntity(url, body, JsonNode.class);
                    JsonNode payload = response.getBody();
                    if (payload != null && payload.path("errors").isArray() && payload.path("errors").size() > 0) {
                        JsonNode maybePlan = payload.path("data").path("plan");
                        if (!(maybePlan.isMissingNode() || maybePlan.isNull())) {
                            return payload;
                        }
                        continue;
                    }
                    if (payload != null) {
                        return payload;
                    }
                } catch (RestClientException ex) {
                    lastError = new OtpException("OTP GraphQL request failed for URL: " + url, ex);
                }
            }
        }
        if (lastError != null) {
            throw lastError;
        }
        throw new OtpException("OTP GraphQL request failed with no candidate endpoints tried", null);
    }

    private double[] parseLatLon(String value) {
        if (value == null) {
            throw new OtpException("Expected 'lat,lon' input but got null", null);
        }
        String[] parts = value.split(",");
        if (parts.length != 2) {
            throw new OtpException("Expected 'lat,lon' input but got: " + value, null);
        }
        try {
            return new double[]{Double.parseDouble(parts[0].trim()), Double.parseDouble(parts[1].trim())};
        } catch (NumberFormatException ex) {
            throw new OtpException("Invalid 'lat,lon' numeric input: " + value, ex);
        }
    }

    private JsonNode getJson(String url) {
        try {
            ResponseEntity<JsonNode> response = otpRestTemplate.getForEntity(url, JsonNode.class);
            return response.getBody();
        } catch (RestClientException ex) {
            throw new OtpException("OTP request failed for URL: " + url, ex);
        }
    }
}
