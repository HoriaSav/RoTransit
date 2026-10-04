package com.example.RoTransit.controller;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedUpdateJob;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

@RestController
public class FeedController {

    private final FeedRepository feeds;
    private final FeedUpdateJob feedUpdateJob;

    public FeedController(FeedRepository feeds, FeedUpdateJob feedUpdateJob) {
        this.feeds = feeds;
        this.feedUpdateJob = feedUpdateJob;
    }

    @GetMapping("/feeds")
    public List<Feed> getFeedList() {
        return feeds.findAll();
    }

    @PostMapping("/feeds")
    public Feed createFeed(@RequestBody Feed feed) {
        feed.setDownloadedAt(Instant.now());
        return feeds.save(feed);
    }

    @GetMapping("/feeds/{id}")
    public Feed getFeedById(@PathVariable Long id) {
        return feeds.findById(id).orElseThrow();
    }

    // TODO: declare IOException and InterruptedException instead of Exception, and return 502 when the URL is down

    @PostMapping("/feeds/{id}/download")
    public Feed downloadFeedById(@PathVariable Long id) throws Exception {

        Feed feed = feeds.findById(id).orElseThrow();
        String fileName = id + "_" + feed.getCityName() + "_" + feed.getCompanyName() + ".zip";
        Path file = Path.of("feeds", fileName);
        String sourceUrl = "https://files.mobilitydatabase.org/" + feed.getSourceId() + "/latest.zip";

        Files.createDirectories(file.getParent());

        HttpClient client = HttpClient.newHttpClient();
        HttpRequest request = HttpRequest.newBuilder(URI.create(sourceUrl)).GET().build();
        client.send(request, HttpResponse.BodyHandlers.ofFile(file));

        feed.setLocalPath(file.toString());
        feed.setStatus("downloaded");
        feed.setSourceUrl(sourceUrl);
        feed.setDownloadedAt(Instant.now());

        return feeds.save(feed);
    }

    @GetMapping("/feeds/{id}/file")
    public ResponseEntity<Resource> getFeedFile(@PathVariable Long id) {
        Feed feed = feeds.findById(id).orElseThrow();
        if (feed.getLocalPath() == null || feed.getLocalPath().isBlank()) {
            throw new IllegalStateException("feed file is missing");
        }
        Path file = Path.of(feed.getLocalPath());
        if (!Files.isRegularFile(file)) {
            throw new IllegalStateException("feed file is missing");
        }
        String fileName = file.getFileName().toString();
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("application/zip"))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + fileName + "\"")
                .body(new FileSystemResource(file));
    }

    @GetMapping("/feeds/{id}/expires")
    public LocalDate getFeedExpireDate(@PathVariable Long id) throws Exception {
        Feed feed = feeds.findById(id).orElseThrow();
        String fileName = "feed_info.txt";

        try (ZipFile zip = new ZipFile(Path.of(feed.getLocalPath()).toFile())) {
            ZipEntry entry = zip.getEntry(fileName);
            if (entry == null) {
                throw new IllegalStateException(fileName + " is missing");
            }
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(zip.getInputStream(entry), StandardCharsets.UTF_8))) {
                String header = reader.readLine();
                if (header == null) {
                    throw new IllegalStateException(fileName + " is missing feed_end_date");
                }
                String[] columns = header.split(",");
                int endDate = -1;
                for (int i = 0; i < columns.length; i++) {
                    if ("feed_end_date".equals(columns[i].trim())) {
                        endDate = i;
                        break;
                    }
                }
                if (endDate < 0) {
                    throw new IllegalStateException(fileName + " is missing feed_end_date");
                }
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.isBlank()) {
                        continue;
                    }
                    String[] fields = line.split(",");
                    return LocalDate.parse(fields[endDate].trim(), DateTimeFormatter.BASIC_ISO_DATE);
                }
                throw new IllegalStateException(fileName + " has no data");
            }
        }
    }

    @PostMapping("/feeds/update")
    public List <String> updateFeedsNow() {
        return feedUpdateJob.updateFeeds();
    }
}
