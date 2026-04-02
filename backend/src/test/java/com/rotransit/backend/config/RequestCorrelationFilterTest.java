package com.rotransit.backend.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class RequestCorrelationFilterTest {

    private final RequestCorrelationFilter filter = new RequestCorrelationFilter();

    @Test
    void doFilterInternalReusesIncomingRequestId() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader(RequestCorrelationFilter.REQUEST_ID_HEADER, "req-123");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        assertEquals("req-123", request.getAttribute(RequestCorrelationFilter.REQUEST_ID_ATTR));
        assertEquals("req-123", response.getHeader(RequestCorrelationFilter.REQUEST_ID_HEADER));
        assertNull(MDC.get(RequestCorrelationFilter.REQUEST_ID_ATTR));
    }

    @Test
    void doFilterInternalGeneratesRequestIdWhenHeaderMissing() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        String generated = response.getHeader(RequestCorrelationFilter.REQUEST_ID_HEADER);
        assertNotNull(generated);
        assertFalse(generated.isBlank());
        assertEquals(generated, request.getAttribute(RequestCorrelationFilter.REQUEST_ID_ATTR));
    }
}
