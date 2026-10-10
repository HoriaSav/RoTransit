package com.example.RoTransit.controller;

import com.example.RoTransit.dto.CreateFeedRequest;
import com.example.RoTransit.dto.FeedDetails;
import com.example.RoTransit.dto.FeedStatus;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedSourceRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import com.example.RoTransit.service.DownloadResult;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/admin")
public class AdminController {
    private final FeedRepository feeds;
    private final FeedSourceRepository sources;
    private final FeedVersionRepository versions;
    private final FeedService feedService;
    private final FeedUpdateJob feedUpdateJob;
    private final Clock clock;

    public AdminController(FeedRepository feeds, FeedSourceRepository sources, FeedVersionRepository versions,
                           FeedService feedService, FeedUpdateJob feedUpdateJob, Clock clock) {
        this.feeds = feeds;
        this.sources = sources;
        this.versions = versions;
        this.feedService = feedService;
        this.feedUpdateJob = feedUpdateJob;
        this.clock = clock;
    }

    @GetMapping("/feeds")
    public List<FeedStatus> feeds(){
        // four queries in total (feeds, current, latest, upcoming), not one per feed
        Map<Long, FeedVersion> current = versions.findCurrentByFeedId();
        Map<Long, FeedVersion> latest = versions.findLatestByFeedId();
        Map<Long, FeedVersion> upcoming = versions.findUpcomingByFeedId();
        LocalDate today = LocalDate.now(clock);
        return feeds.findAll().stream()
                .map(feed -> FeedStatus.from(feed, current.get(feed.getId()), latest.get(feed.getId()),
                        upcoming.get(feed.getId()), today))
                .sorted(Comparator.comparing(FeedStatus::expiresOn,
                        Comparator.nullsFirst(Comparator.naturalOrder()))
                        .thenComparing(FeedStatus::id))
                .toList();
    }

    @PostMapping("/feeds")
    public FeedDetails createFeed(@RequestBody CreateFeedRequest request) {
        Feed feed = feedService.createFeed(request.cityName(), request.companyName(), request.sourceId());
        return details(feed);
    }

    @GetMapping("/feeds/{id}")
    public FeedDetails getFeedById(@PathVariable Long id) {
        return details(feeds.findById(id).orElseThrow());
    }

    @PostMapping("/feeds/{id}/download")
    public FeedDetails downloadFeedById(@PathVariable Long id) throws IOException, InterruptedException {
        DownloadResult result = feedService.download(id);
        return details(result.version().getFeed()).withUnchanged(result.unchanged());
    }

    /** Manual override: switch to the upcoming version now instead of waiting for its start date. */
    @PostMapping("/feeds/{id}/promote")
    public FeedDetails promoteFeedById(@PathVariable Long id) {
        Feed feed = feeds.findById(id).orElseThrow(); // unknown id -> 404 "Feed not found"
        feedService.promoteUpcoming(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "feed has no upcoming version"));
        return details(feed);
    }

    @GetMapping("/feeds/{id}/expires")
    public LocalDate getFeedExpireDate(@PathVariable Long id) throws IOException {
        return feedService.getExpireDate(id);
    }

    // out.flush() only reaches the client because spring.properties sets spring.http.response.flush.enabled=true
    @PostMapping("/feeds/update")
    public ResponseEntity<StreamingResponseBody> updateFeedsNow() {
        StreamingResponseBody body = out -> feedUpdateJob.updateFeeds(line -> {
            try {
                out.write((line + "\n").getBytes(StandardCharsets.UTF_8));
                out.flush();
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        });
        return ResponseEntity.ok().contentType(MediaType.TEXT_PLAIN).body(body);
    }

    private FeedDetails details(Feed feed) {
        return FeedDetails.from(feed,
                sources.findByFeedIdAndPriority(feed.getId(), 1).orElse(null),
                versions.findByFeedIdAndStatus(feed.getId(), FeedVersion.CURRENT).orElse(null),
                versions.findFirstByFeedIdOrderByIdDesc(feed.getId()).orElse(null),
                versions.findByFeedIdAndStatus(feed.getId(), FeedVersion.UPCOMING).orElse(null));
    }
}
