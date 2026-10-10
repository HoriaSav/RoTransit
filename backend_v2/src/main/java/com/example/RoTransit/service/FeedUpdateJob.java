package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.function.Consumer;

@Service
public class FeedUpdateJob {
    private final FeedRepository feeds;
    private final FeedVersionRepository versions;
    private final FeedService feedService;
    private final Clock clock;
    private static final Logger log = LoggerFactory.getLogger(FeedUpdateJob.class);

    public FeedUpdateJob(FeedRepository feedRepository, FeedVersionRepository versions, FeedService service,
                         Clock clock) {
        this.feeds = feedRepository;
        this.versions = versions;
        this.feedService = service;
        this.clock = clock;
    }

    @Scheduled(cron = "0 0 4 * * *")
    public void updateFeedsScheduled() {
        updateFeeds(line -> {});
    }

    /**
     * At startup: clean up files left by a crash, and, if the server was down at 04:00, promote the upcoming versions
     * that started meanwhile instead of serving yesterday's timetable for another day.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void promoteOnStartup() {
        feedService.sweepOrphanFiles(); // never throws, only logs
        try {
            promoteDue(feeds.findAll(), line -> log.info(line));
        }
        catch (RuntimeException e) {
            // never stop the app from starting; the 04:00 run tries again
            log.error("Promoting upcoming versions at startup failed", e);
        }
    }

    /**
     * Makes every upcoming version whose start date has come the current one. allFeeds comes from feeds.findAll(),
     * which loads the cities too, so the city names below need no extra query (and no open session).
     */
    void promoteDue(List<Feed> allFeeds, Consumer<String> onResult) {
        LocalDate today = LocalDate.now(clock);
        Map<Long, Feed> feedsById = allFeeds.stream().collect(Collectors.toMap(Feed::getId, Function.identity()));
        for (FeedVersion upcoming : versions.findUpcomingByFeedId().values()) {
            if (upcoming.getStartsOn() == null || upcoming.getStartsOn().isAfter(today)) {
                continue; // not due yet
            }
            Long feedId = upcoming.getFeed().getId();
            String city = feedsById.containsKey(feedId) ? feedsById.get(feedId).getCityName() : "feed " + feedId;
            try {
                if (feedService.promoteUpcoming(feedId).isPresent()) {
                    onResult.accept(city + " switched to the version starting " + upcoming.getStartsOn());
                }
            }
            catch (RuntimeException e) {
                // one broken feed must not keep the others on yesterday's timetable
                log.error("Could not switch {} to its upcoming version", city, e);
                onResult.accept(city + " failed to switch, " + e.getMessage());
            }
        }
    }

    /** A feed whose source sent the same file again less than this long ago is not downloaded again. */
    static final Duration RECHECK_AFTER = Duration.ofHours(24);
    private static final DateTimeFormatter CHECKED_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

    public void updateFeeds(Consumer<String> onResult) {
        feedService.sweepOrphanFiles(); // never throws, only logs
        List<Feed> allFeeds = feeds.findAll();
        // switch first, so the download decisions below already see the promoted versions
        promoteDue(allFeeds, onResult);
        // one query each for all current and upcoming versions instead of one per feed
        Map<Long, FeedVersion> currentVersions = versions.findCurrentByFeedId();
        Map<Long, FeedVersion> upcomingVersions = versions.findUpcomingByFeedId();
        LocalDate today = LocalDate.now(clock);
        for (Feed feed : allFeeds) {
            String result;
            try {
                FeedVersion current = currentVersions.get(feed.getId());
                String filePath = current == null ? null : current.getFilePath();
                boolean missing = filePath == null || filePath.isBlank() || !Files.isRegularFile(Path.of(filePath));
                // judged on the newest file we have: with an upcoming version covering the next weeks there is
                // nothing to fetch, even though the current one is about to expire
                FeedVersion newest = upcomingVersions.getOrDefault(feed.getId(), current);
                LocalDate expires = newest == null ? null : newest.getExpiresOn();
                boolean expiring = expires == null || expires.isBefore(today.plusDays(7));

                Instant checkedAt = lastChecked(current, upcomingVersions.get(feed.getId()));
                boolean checkedRecently = checkedAt != null && checkedAt.isAfter(clock.instant().minus(RECHECK_AFTER));

                if (expiring && !missing && checkedRecently) {
                    // the source sent this exact file again a few hours ago; asking again tonight won't change that
                    String checked = CHECKED_FORMAT.format(checkedAt.atZone(clock.getZone()));
                    log.info("{} unchanged at the source, checked {}", feed.getCityName(), checked);
                    result = feed.getCityName() + " unchanged at the source, checked " + checked;
                }
                else if (missing || expiring) {
                    DownloadResult download = feedService.download(feed.getId());
                    // "unchanged" is not "up to date": we did download, but the source has nothing newer yet
                    // (worth knowing when our file is about to expire)
                    if (download.unchanged()) {
                        log.info("{} is unchanged", feed.getCityName());
                        result = feed.getCityName() + " is unchanged";
                    }
                    else if (FeedVersion.UPCOMING.equals(download.version().getStatus())) {
                        log.info("{} has a new version starting {}", feed.getCityName(), download.version().getStartsOn());
                        result = feed.getCityName() + " has a new version starting " + download.version().getStartsOn();
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

    /** The latest "same file again" check of either version (the source may have sent either one). */
    private static Instant lastChecked(FeedVersion current, FeedVersion upcoming) {
        Instant a = current == null ? null : current.getCheckedAt();
        Instant b = upcoming == null ? null : upcoming.getCheckedAt();
        if (a == null) {
            return b;
        }
        return b == null || a.isAfter(b) ? a : b;
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
