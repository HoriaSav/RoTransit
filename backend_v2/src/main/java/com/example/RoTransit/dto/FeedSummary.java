package com.example.RoTransit.dto;

import com.example.RoTransit.entity.Feed;

public record FeedSummary (Long id, String cityName, String companyName){
    public static FeedSummary from (Feed feed) {
        return new FeedSummary(feed.getId(), feed.getCityName(), feed.getCompanyName());
    }
}
