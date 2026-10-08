package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.function.Consumer;

@Service
public class FeedUpdateJob {
    private final FeedRepository feeds;
    private final FeedService feedService;
    private static final Logger log = LoggerFactory.getLogger(FeedUpdateJob.class);

    public FeedUpdateJob(FeedRepository feedRepository, FeedService service) {
        this.feeds = feedRepository;
        this.feedService = service;
    }

    @Scheduled(cron = "0 0 4 * * *")
    public void updateFeedsScheduled() {
        updateFeeds(line -> {});
    }

    public void updateFeeds(Consumer<String> onResult) {
        for (Feed feed : feeds.findAll()) {
            String result;
            try {
                boolean missing = feed.getLocalPath() == null || feed.getLocalPath().isBlank() || !Files.isRegularFile(Path.of(feed.getLocalPath()));
                LocalDate expires = feed.getExpiresOn();
                boolean expiring = expires == null || expires.isBefore(LocalDate.now().plusDays(7));

                if (missing || expiring) {
                    feedService.download(feed.getId());
                    logSuccessfulDownload(feed);
                    result = feed.getCityName() + " has been updated!";
                }
                else {
                    logIsUpToDate(feed);
                    result = feed.getCityName() + " is up to date!";
                }
            }
            catch (InterruptedException e) {
                // the app is shutting down or someone cancelled the job: stop instead of failing every remaining feed
                Thread.currentThread().interrupt();
                log.warn("Feed update interrupted at {}, stopping", feed.getCityName());
                onResult.accept(feed.getCityName() + " interrupted, update stopped");
                return;
            }
            catch (Exception e) {
                logFailedDownload(feed, e);
                feeds.findById(feed.getId()).ifPresent(fresh -> {
                    fresh.setStatus("failed");
                    feeds.save(fresh);
                });
                result = feed.getCityName() + " failed, " + e.getMessage();
            }
            onResult.accept(result);
        }
    }

    private void logSuccessfulDownload(Feed feed) {
        log.info("Downloaded new feed for {}", feed.getCityName());
    }

    private void logFailedDownload(Feed feed, Exception e) {
        log.error("Feed update failed for {} (id {})", feed.getCityName(), feed.getId(), e);
    }

    private void logIsUpToDate(Feed feed) {
        log.debug("{} is up to date",feed.getCityName());
    }
}
