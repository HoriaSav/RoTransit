package com.example.RoTransit.service;

import com.example.RoTransit.entity.FeedVersion;

/**
 * What FeedService.download did. unchanged = true: the source sent exactly the file we already serve (same sha256),
 * so no new version was made and version is the existing current one.
 */
public record DownloadResult(FeedVersion version, boolean unchanged) {
}
