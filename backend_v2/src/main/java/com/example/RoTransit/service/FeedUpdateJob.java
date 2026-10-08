package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.Map;
import java.util.function.Consumer;

@Service
public class FeedUpdateJob {
    private final FeedRepository feeds;
    private final FeedVersionRepository versions;
    private final FeedService feedService;
    private static final Logger log = LoggerFactory.getLogger(FeedUpdateJob.class);

    public FeedUpdateJob(FeedRepository feedRepository, FeedVersionRepository versions, FeedService service) {
        this.feeds = feedRepository;
        this.versions = versions;
        this.feedService = service;
    }

    @Scheduled(cron = "0 0 4 * * *")
    public void updateFeedsScheduled() {
        updateFeeds(line -> {});
    }

    public void updateFeeds(Consumer<String> onResult) {
        // one query for all current versions instead of one per feed
        Map<Long, FeedVersion> currentVersions = versions.findCurrentByFeedId();
        for (Feed feed : feeds.findAll()) {
            String result;
            try {
                FeedVersion current = currentVersions.get(feed.getId());
                String filePath = current == null ? null : current.getFilePath();
                boolean missing = filePath == null || filePath.isBlank() || !Files.isRegularFile(Path.of(filePath));
                LocalDate expires = current == null ? null : current.getExpiresOn();
                boolean expiring = expires == null || expires.isBefore(LocalDate.now().plusDays(7));

                if (missing || expiring) {
                    // "unchanged" is not "up to date": we did download, but the source has nothing newer yet
                    // (worth knowing when our file is about to expire)
                    if (feedService.download(feed.getId()).unchanged()) {
                        log.info("{} is unchanged", feed.getCityName());
                        result = feed.getCityName() + " is unchanged";
                    }
                    else {
                        logSuccessfulDownload(feed);
                        result = feed.getCityName() + " has been updated!";
                    }
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
                // no need to save anything here: download() already stored the failed attempt
                logFailedDownload(feed, e);
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
