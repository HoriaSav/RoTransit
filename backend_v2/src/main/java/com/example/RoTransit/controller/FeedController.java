package com.example.RoTransit.controller;

import com.example.RoTransit.dto.FeedOperator;
import com.example.RoTransit.dto.FeedSummary;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import com.example.RoTransit.repository.OperatorRepository;
import com.example.RoTransit.service.FeedService;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.data.domain.Sort;
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
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/feeds")
public class FeedController {

    private final FeedRepository feeds;
    private final FeedVersionRepository versions;
    private final OperatorRepository operators;

    public FeedController(FeedRepository feeds, FeedVersionRepository versions, OperatorRepository operators) {
        this.feeds = feeds;
        this.versions = versions;
        this.operators = operators;
    }

    @GetMapping
    public List<FeedSummary> getPublicFeedList() {
        // two queries in total (feeds with their cities, then all operator names), not one per feed
        Map<Long, List<String>> operatorNames = operators.findCurrentOperatorNames().stream()
                .collect(Collectors.groupingBy(FeedOperator::feedId,
                        Collectors.mapping(FeedOperator::name, Collectors.toList())));
        return feeds.findAll(Sort.by("id")).stream()
                .map(feed -> FeedSummary.from(feed, operatorNames.getOrDefault(feed.getId(), List.of())))
                .toList();
    }

    @GetMapping("/{id}/file")
    public ResponseEntity<Resource> getFeedFile(@PathVariable Long id) throws IOException {
        feeds.findById(id).orElseThrow(); // unknown id -> 404 "Feed not found"
        String filePath = versions.findByFeedIdAndStatus(id, FeedVersion.CURRENT)
                .map(FeedVersion::getFilePath)
                .orElse(null);
        if (filePath == null || filePath.isBlank()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        Path file = Path.of(filePath);
        if (!Files.isRegularFile(file) || !Files.isDirectory(FeedService.FEEDS_ROOT)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        // toRealPath follows symlinks, so a link inside feeds/ that points outside is rejected too
        if (!file.toRealPath().startsWith(FeedService.FEEDS_ROOT.toRealPath())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        // the file on disk is named after its sha256; clients keep getting the simple name they always got
        String fileName = id + ".zip";
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("application/zip"))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + fileName + "\"")
                .body(new FileSystemResource(file));
    }
}
