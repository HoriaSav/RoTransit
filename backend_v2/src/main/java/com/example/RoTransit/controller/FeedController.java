package com.example.RoTransit.controller;

import com.example.RoTransit.dto.CreateFeedRequest;
import com.example.RoTransit.dto.FeedSummary;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

@RestController
public class FeedController {

    private final FeedRepository feeds;
    private final FeedUpdateJob feedUpdateJob;
    private final FeedService feedService;

    public FeedController(FeedRepository feeds, FeedUpdateJob feedUpdateJob, FeedService feedService) {
        this.feeds = feeds;
        this.feedUpdateJob = feedUpdateJob;
        this.feedService = feedService;
    }

    @GetMapping("/feeds")
    public List<Feed> getFeedList() {
        return feeds.findAll();
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

    @GetMapping("/feeds/{id}/file")
    public ResponseEntity<Resource> getFeedFile(@PathVariable Long id) throws IOException {
        Feed feed = feeds.findById(id).orElseThrow();
        if (feed.getLocalPath() == null || feed.getLocalPath().isBlank()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        Path file = Path.of(feed.getLocalPath());
        if (!Files.isRegularFile(file) || !Files.isDirectory(FeedService.FEEDS_ROOT)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        // toRealPath follows symlinks, so a link inside feeds/ that points outside is rejected too
        if (!file.toRealPath().startsWith(FeedService.FEEDS_ROOT.toRealPath())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        String fileName = file.getFileName().toString();
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("application/zip"))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + fileName + "\"")
                .body(new FileSystemResource(file));
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

    @GetMapping("/api/feeds")
    public List<FeedSummary> getPublicFeedList() {
        return feeds.findAll().stream().map(FeedSummary::from).toList();
    }
}
