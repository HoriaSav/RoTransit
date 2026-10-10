package com.rotransit.backend.controller;

import org.junit.platform.suite.api.SelectClasses;
import org.junit.platform.suite.api.Suite;

@Suite
@SelectClasses({
        CityControllerIntegrationTest.class,
        RouteControllerIntegrationTest.class,
        TransitCatalogControllerIntegrationTest.class,
        HealthControllerIntegrationTest.class
})
class BackendIntegrationSuite {
}
