package com.rotransit.backend.controller;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Makes {@code GET /} return a small JSON body so a browser check at the base URL is not an "empty" page.
 * Health remains at {@code GET /api/health}.
 */
@RestController
public class ApiRootController {

    @GetMapping("/")
    public Map<String, String> root() {
        return Map.of(
                "service", "rotransit-backend",
                "health", "/api/health",
                "hint", "Open /api/health for a simple ok check."
        );
    }
}
