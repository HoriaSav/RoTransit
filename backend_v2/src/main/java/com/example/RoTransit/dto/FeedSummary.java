package com.example.RoTransit.dto;

import com.example.RoTransit.entity.Feed;

import java.util.List;

// companyName keeps its old name for API compatibility; it is the feed name now
public record FeedSummary (Long id, String cityName, String companyName, List<String> operators){
    public static FeedSummary from (Feed feed, List<String> operators) {
        return new FeedSummary(feed.getId(), feed.getCityName(), feed.getName(), operators);
    }
}
