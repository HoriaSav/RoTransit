package com.rotransit.backend.config;

import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.web.client.RestTemplate;

class HttpClientConfigTest {

    @Mock
    private RestTemplateBuilder builder;

    @Mock
    private RestTemplate restTemplate;

    private HttpClientConfig httpClientConfig;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        httpClientConfig = new HttpClientConfig();
    }

    @Test
    void otpRestTemplateUsesExpectedTimeouts() {
        when(builder.setConnectTimeout(Duration.ofSeconds(5))).thenReturn(builder);
        when(builder.setReadTimeout(Duration.ofSeconds(12))).thenReturn(builder);
        when(builder.build()).thenReturn(restTemplate);

        RestTemplate built = httpClientConfig.otpRestTemplate(builder);

        assertSame(restTemplate, built);
        verify(builder).setConnectTimeout(Duration.ofSeconds(5));
        verify(builder).setReadTimeout(Duration.ofSeconds(12));
        verify(builder).build();
    }
}
