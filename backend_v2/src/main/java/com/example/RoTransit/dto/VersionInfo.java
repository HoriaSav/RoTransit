package com.example.RoTransit.dto;

import com.example.RoTransit.entity.FeedVersion;

import java.time.Instant;
import java.time.LocalDate;

/**
 * What a client needs to know about one version: sha256 tells it whether the file it has is still the right one
 * (it is also the ETag of the file endpoints).
 */
public record VersionInfo(String sha256, LocalDate startsOn, LocalDate expiresOn, Instant downloadedAt) {

    /** null in, null out, so a missing version shows as "current": null / "upcoming": null in the JSON. */
    public static VersionInfo from(FeedVersion version) {
        if (version == null) {
            return null;
        }
        return new VersionInfo(version.getSha256(), version.getStartsOn(), version.getExpiresOn(),
                version.getDownloadedAt());
    }
}
