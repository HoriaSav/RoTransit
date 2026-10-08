package com.example.RoTransit.dto;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;

import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

public record FeedStatus(Long id, String cityName, String companyName, String status, Instant downloadedAt,
                         LocalDate expiresOn, Long daysLeft) {

    /** current: the version we serve (or null); latest: the newest attempt, successful or failed (or null). */
    public static FeedStatus from(Feed feed, FeedVersion current, FeedVersion latest) {
        Instant downloadedAt = current == null ? null : current.getDownloadedAt();
        LocalDate expiresOn = current == null ? null : current.getExpiresOn();
        Long daysLeft = expiresOn == null
                ?null
                : ChronoUnit.DAYS.between(LocalDate.now(), expiresOn);
        return new FeedStatus(feed.getId(), feed.getCityName(), feed.getName(), statusOf(current, latest),
                downloadedAt, expiresOn, daysLeft);
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
