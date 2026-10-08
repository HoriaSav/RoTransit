package com.example.RoTransit.controller;

import com.example.RoTransit.dto.CreateFeedRequest;
import com.example.RoTransit.dto.FeedStatus;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;

@RestController
@RequestMapping("/admin")
public class AdminController {
    private final FeedRepository feeds;
    private final FeedService feedService;
    private final FeedUpdateJob feedUpdateJob;

    public AdminController(FeedRepository feeds, FeedService feedService, FeedUpdateJob feedUpdateJob) {
        this.feeds = feeds;
        this.feedService = feedService;
        this.feedUpdateJob = feedUpdateJob;
    }

    @GetMapping("/feeds")
    public List<FeedStatus> feeds(){
        return feeds.findAll().stream().map(FeedStatus::from)
                .sorted(Comparator.comparing(FeedStatus::expiresOn,
                        Comparator.nullsFirst(Comparator.naturalOrder()))
                        .thenComparing(FeedStatus::id))
                .toList();
    }

    @PostMapping("/feeds")
    public Feed createFeed(@RequestBody CreateFeedRequest request) {
        Feed feed = new Feed();
        feed.setCityName(request.cityName());
        feed.setCompanyName(request.companyName());
        feed.setSourceId(request.sourceId());
        feed.setDownloadedAt(Instant.now());
        return feeds.save(feed);
    }

    @GetMapping("/feeds/{id}")
    public Feed getFeedById(@PathVariable Long id) {
        return feeds.findById(id).orElseThrow();
    }

    @PostMapping("/feeds/{id}/download")
    public Feed downloadFeedById(@PathVariable Long id) throws IOException, InterruptedException {
        return feedService.download(id);
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
}
