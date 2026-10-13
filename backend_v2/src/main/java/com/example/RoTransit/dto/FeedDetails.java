package com.example.RoTransit.dto;

import com.example.RoTransit.entity.Feed;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.example.RoTransit.entity.FeedSource;
import com.example.RoTransit.entity.FeedVersion;

import java.time.Instant;
import java.time.LocalDate;

/**
 * One feed for the admin API, with the same fields the old Feed entity had in its JSON (plus startsOn).
 * sourceId is the priority-1 source ref; sourceUrl is the URL the current file was downloaded from.
 * upcoming is the version waiting for its start date, or null.
 * unchanged is only set by POST /admin/feeds/{id}/download (true: the source sent the file we already had);
 * NON_NULL leaves it out of every other response.
 */
public record FeedDetails(Long id, String cityName, String companyName, String sourceId, String sourceUrl,
                          String status, Instant downloadedAt, LocalDate startsOn, LocalDate expiresOn,
                          VersionInfo upcoming,
                          @JsonInclude(JsonInclude.Include.NON_NULL) Boolean unchanged) {

    public static FeedDetails from(Feed feed, FeedSource source, FeedVersion current, FeedVersion latest,
                                   FeedVersion upcoming) {
        String sourceId = source == null ? null : source.getRef();
        String sourceUrl = current == null || current.getSource() == null ? null : current.getSource().downloadUrl();
        return new FeedDetails(feed.getId(), feed.getCityName(), feed.getName(), sourceId, sourceUrl,
                FeedStatus.statusOf(current, latest),
                current == null ? null : current.getDownloadedAt(),
                current == null ? null : current.getStartsOn(),
                current == null ? null : current.getExpiresOn(),
                VersionInfo.from(upcoming),
                null);
    }

    public FeedDetails withUnchanged(boolean unchanged) {
        return new FeedDetails(id, cityName, companyName, sourceId, sourceUrl, status, downloadedAt, startsOn,
                expiresOn, upcoming, unchanged);
    }
}
