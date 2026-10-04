package com.example.RoTransit.service;

import com.example.RoTransit.controller.FeedController;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

@Service
public class FeedUpdateJob {
    private final FeedRepository feeds;
    private final FeedController feedController;

    @Lazy
    public FeedUpdateJob(FeedRepository feedRepository, FeedController controller) {
        this.feeds = feedRepository;
        this.feedController = controller;
    }

    @Scheduled(cron = "0 0 4 * * *")
    public List <String> updateFeeds(){
        List <String> updatedFeeds = new ArrayList<>();
        for (Feed feed : feeds.findAll()) {
            try {
                boolean missing = feed.getLocalPath() == null || feed.getLocalPath().isBlank() || !Files.isRegularFile(Path.of(feed.getLocalPath()));
                if (missing) {
                    feedController.downloadFeedById(feed.getId());
                    updatedFeeds.add(feed.getCityName() + " has been updated!");
                    continue;
                }
                LocalDate expires = feedController.getFeedExpireDate(feed.getId());
                if (expires.isBefore(LocalDate.now().plusDays(7))) {
                    feedController.downloadFeedById(feed.getId());
                    updatedFeeds.add(feed.getCityName() + " has been updated!");
                    continue;
                }
                updatedFeeds.add(feed.getCityName() + " is up to date!");
            }
            catch (Exception ignored) {
                updatedFeeds.add(feed.getCityName() + " failed");
            }
        }
        return updatedFeeds;
    }
}
