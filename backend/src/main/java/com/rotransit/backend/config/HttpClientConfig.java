package com.rotransit.backend.config;

import java.time.Duration;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

@Configuration
public class HttpClientConfig {

    /**
     * Parallel OTP plan calls when resolving same-named stops; virtual threads keep threads cheap while
     * {@link org.springframework.web.client.RestTemplate} blocks.
     */
    @Bean(destroyMethod = "shutdown")
    @Qualifier("stopResolveExecutor")
    public ExecutorService stopResolveExecutor() {
        return Executors.newVirtualThreadPerTaskExecutor();
    }

    @Bean
    public RestTemplate otpRestTemplate(RestTemplateBuilder builder) {
        return builder
                .setConnectTimeout(Duration.ofSeconds(5))
                .setReadTimeout(Duration.ofSeconds(12))
                .build();
    }
}
