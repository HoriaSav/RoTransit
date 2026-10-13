package com.example.RoTransit.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.time.ZoneId;

/**
 * "Today" for the whole app. Timetables change at midnight Romanian time, whatever zone the server runs in, and
 * tests can pass a fixed Clock instead of depending on the real date.
 */
@Configuration
public class ClockConfig {

    @Bean
    public Clock clock() {
        return Clock.system(ZoneId.of("Europe/Bucharest"));
    }
}
