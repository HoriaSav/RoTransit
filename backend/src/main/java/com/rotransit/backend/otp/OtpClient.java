package com.rotransit.backend.otp;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.RouteSearchQuery;
import java.util.List;

public interface OtpClient {

    JsonNode searchRoutes(String otpBaseUrl, RouteSearchQuery query);

    JsonNode searchRoutesWithWindow(String otpBaseUrl, RouteSearchQuery query, int searchWindowMinutes);

    List<JsonNode> findNearbyStops(String otpBaseUrl, double latitude, double longitude, int radiusMeters);

    long totalHttpCalls();
}
