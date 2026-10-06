package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

@Service
public class FeedService {
    public static final Path FEEDS_ROOT = Path.of("feeds");

    private final FeedRepository feeds;
    private final HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    public FeedService(FeedRepository feeds) {
        this.feeds = feeds;
    }

    public Feed download(Long id) throws IOException, InterruptedException {
        Feed feed = feeds.findById(id).orElseThrow();
        Path file = FEEDS_ROOT.resolve(id + ".zip");
        String sourceUrl = "https://files.mobilitydatabase.org/" + feed.getSourceId() + "/latest.zip";

        Files.createDirectories(FEEDS_ROOT);

        HttpRequest request = HttpRequest.newBuilder(URI.create(sourceUrl)).GET().build();

        Path temp = Files.createFile(FEEDS_ROOT.resolve(id + "-" + UUID.randomUUID() + ".zip.part"));
        try {
            HttpResponse<Path> response = client.send(request, HttpResponse.BodyHandlers.ofFile(temp));

            if (response.statusCode() != 200) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                        "source returned " + response.statusCode() + " for " + sourceUrl);
            }
            Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } finally {
            // after a successful move the temp file is gone, so this only cleans up failures
            Files.deleteIfExists(temp);
        }

        feed.setLocalPath(file.toString());
        feed.setStatus("downloaded");
        feed.setSourceUrl(sourceUrl);
        feed.setDownloadedAt(Instant.now());

        return feeds.save(feed);
    }

    // TODO: when feed_info.txt or feed_end_date is missing (Cluj's zip has no feed_info.txt),
    // fall back to the latest end_date in calendar.txt, then to the latest date in calendar_dates.txt,
    // and throw only if none of them has a date. Extract a private helper
    // LocalDate latestDate(ZipFile zip, String fileName, String column) that returns null when the file or column is missing.
    public LocalDate getExpireDate(Long id) throws IOException {
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
}
