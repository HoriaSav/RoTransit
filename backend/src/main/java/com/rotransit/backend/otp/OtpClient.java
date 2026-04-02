package com.rotransit.backend.otp;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.service.RouteSearchQuery;
import java.util.List;

public interface OtpClient {

    JsonNode searchRoutes(String otpBaseUrl, RouteSearchQuery query);

    List<JsonNode> findNearbyStops(String otpBaseUrl, double latitude, double longitude, int radiusMeters);

    List<JsonNode> searchStops(String otpBaseUrl, String query, int limit);

    List<JsonNode> listBusRoutes(String otpBaseUrl);

    List<JsonNode> listRouteStops(String otpBaseUrl, String routeId, String directionId);

    List<JsonNode> routeStopTimes(String otpBaseUrl, String routeId, String stopId, String serviceDate);
}
