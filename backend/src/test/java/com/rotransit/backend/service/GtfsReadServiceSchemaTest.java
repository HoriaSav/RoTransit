package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.Locale;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.jupiter.api.Test;

class GtfsReadServiceSchemaTest {

    @Test
    void ensureSchemaBootstrapMethodsAreGone() {
        Set<String> names = Arrays.stream(GtfsReadService.class.getDeclaredMethods())
                .map(Method::getName)
                .map(n -> n.toLowerCase(Locale.ROOT))
                .collect(Collectors.toSet());
        assertFalse(names.contains("ensureschema"));
        assertFalse(names.contains("ensure_schema"));
        assertFalse(names.contains("createschema"));
        assertFalse(names.contains("initSchema".toLowerCase(Locale.ROOT)));
        assertTrue(names.contains("searchstops") || names.contains("findstopsbynormalizedname"));
    }
}
