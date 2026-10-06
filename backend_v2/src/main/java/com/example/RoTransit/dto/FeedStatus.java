package com.example.RoTransit.dto;

import com.example.RoTransit.entity.Feed;

import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

public record FeedStatus(Long id, String cityName, String companyName, String status, Instant downloadedAt,
                         LocalDate expiresOn, Long daysLeft) {
    public static FeedStatus from(Feed feed) {
        Long daysLeft = feed.getExpiresOn() == null
                ?null
                : ChronoUnit.DAYS.between(LocalDate.now(), feed.getExpiresOn());
        return new FeedStatus(feed.getId(), feed.getCityName(),feed.getCompanyName(), feed.getStatus(),
                feed.getDownloadedAt(), feed.getExpiresOn(), daysLeft);
    }
}
