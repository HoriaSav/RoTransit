package com.example.RoTransit;

import com.example.RoTransit.entity.City;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedSource;
import com.example.RoTransit.entity.FeedVersion;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Instant;
import java.time.LocalDate;

/** Builds entities for unit tests. Ids are normally set by the database, so here they are set by reflection. */
public final class TestEntities {
    private TestEntities() {
    }

    public static Feed feed(long id, String cityName, String feedName) {
        City city = new City();
        ReflectionTestUtils.setField(city, "id", id);
        city.setName(cityName);
        Feed feed = new Feed();
        ReflectionTestUtils.setField(feed, "id", id);
        feed.setCity(city);
        feed.setName(feedName);
        return feed;
    }

    public static FeedSource mobilityDbSource(Feed feed, String ref) {
        FeedSource source = new FeedSource();
        ReflectionTestUtils.setField(source, "id", feed.getId());
        source.setFeed(feed);
        source.setKind(FeedSource.MOBILITYDB);
        source.setRef(ref);
        source.setPriority(1);
        return source;
    }

    public static FeedVersion version(long id, Feed feed, String status, String filePath, LocalDate expiresOn) {
        FeedVersion version = new FeedVersion();
        ReflectionTestUtils.setField(version, "id", id);
        version.setFeed(feed);
        version.setStatus(status);
        version.setFilePath(filePath);
        version.setExpiresOn(expiresOn);
        version.setDownloadedAt(Instant.parse("2026-01-01T00:00:00Z"));
        return version;
    }

    public static FeedVersion current(Feed feed, String filePath, LocalDate expiresOn) {
        return version(feed.getId() * 100, feed, FeedVersion.CURRENT, filePath, expiresOn);
    }
}
