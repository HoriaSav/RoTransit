package com.example.RoTransit.dto;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;

import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

public record FeedStatus(Long id, String cityName, String companyName, String status, Instant downloadedAt,
                         LocalDate expiresOn, Long daysLeft, LocalDate upcomingStartsOn) {

    /**
     * current: the version we serve (or null); latest: the newest attempt, successful or failed (or null);
     * upcoming: the version waiting for its start date (or null). today comes from the app's Clock (Bucharest),
     * not the server's zone.
     */
    public static FeedStatus from(Feed feed, FeedVersion current, FeedVersion latest, FeedVersion upcoming,
                                  LocalDate today) {
        Instant downloadedAt = current == null ? null : current.getDownloadedAt();
        LocalDate expiresOn = current == null ? null : current.getExpiresOn();
        Long daysLeft = expiresOn == null
                ?null
                : ChronoUnit.DAYS.between(today, expiresOn);
        return new FeedStatus(feed.getId(), feed.getCityName(), feed.getName(), statusOf(current, latest),
                downloadedAt, expiresOn, daysLeft, upcoming == null ? null : upcoming.getStartsOn());
    }

    /**
     * The status values the API had before the redesign: "new" (never downloaded), "downloaded" (we have a
     * current version) or "failed" (the newest attempt failed; a current version, if any, is still served).
     */
    public static String statusOf(FeedVersion current, FeedVersion latest) {
        if (latest != null && FeedVersion.FAILED.equals(latest.getStatus())) {
            return "failed";
        }
        return current == null ? "new" : "downloaded";
    }
}
