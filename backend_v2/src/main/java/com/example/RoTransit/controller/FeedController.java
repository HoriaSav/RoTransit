package com.example.RoTransit.controller;

import com.example.RoTransit.dto.FeedSummary;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedService;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

@RestController
@RequestMapping("/api/feeds")
public class FeedController {

    private final FeedRepository feeds;

    public FeedController(FeedRepository feeds) {
        this.feeds = feeds;
    }

    @GetMapping
    public List<FeedSummary> getPublicFeedList() {
        return feeds.findAll().stream().map(FeedSummary::from).toList();
    }

    @GetMapping("/{id}/file")
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
}
