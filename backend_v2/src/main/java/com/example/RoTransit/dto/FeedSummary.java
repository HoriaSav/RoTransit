package com.example.RoTransit.dto;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;

import java.util.List;

// companyName keeps its old name for API compatibility; it is the feed name now.
// current/upcoming let the app see whether its stored file is still the right one (compare sha256) without
// downloading anything; both are null when the feed has no such version.
public record FeedSummary (Long id, String cityName, String companyName, List<String> operators,
                           VersionInfo current, VersionInfo upcoming){
    public static FeedSummary from (Feed feed, List<String> operators, FeedVersion current, FeedVersion upcoming) {
        return new FeedSummary(feed.getId(), feed.getCityName(), feed.getName(), operators,
                VersionInfo.from(current), VersionInfo.from(upcoming));
    }
}
