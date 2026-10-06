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
import java.time.format.DateTimeParseException;
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

    public LocalDate getExpireDate(Long id) throws IOException {

        Feed feed = feeds.findById(id).orElseThrow();

        try (ZipFile zip = new ZipFile(Path.of(feed.getLocalPath()).toFile())){
            LocalDate date = latestDate(zip, "feed_info.txt", "feed_end_date");
            if (date == null) date = latestDate(zip, "calendar.txt", "end_date");
            if (date == null) date = latestDate(zip, "calendar_dates.txt", "date");
            if (date == null) throw new IllegalStateException("no expiry date found in " + feed.getLocalPath());
            return date;
        }
    }

    private LocalDate latestDate (ZipFile zip, String fileName, String column) throws IOException {
        ZipEntry entry = zip.getEntry(fileName);
        if (entry == null) {
            return null;
        }
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(zip.getInputStream(entry), StandardCharsets.UTF_8))) {
            String header = reader.readLine();
            if (header == null) {
                return null;
            }
            header = header.replace("\uFEFF", "");

            String[] columns = header.split(",");
            int index = -1;
            for (int i = 0; i < columns.length; i++) {
                if (columns[i].trim().replace("\"", "").equals(column)){
                    index = i;
                    break;
                }
            }
            if (index == -1) {
                return null;
            }

            LocalDate latest = null;
            String line;
            while ((line = reader.readLine()) != null){
                String [] fields = line.split(",", -1);
                if (index >= fields.length) {
                    continue;
                }
                String value = fields[index].trim().replace("\"", "");
                if (value.isEmpty()) {
                    continue;
                }
                try {
                    LocalDate d = LocalDate.parse(value, DateTimeFormatter.BASIC_ISO_DATE);
                    if (latest == null || d.isAfter(latest)) {
                        latest = d;
                    }
                }
                catch (DateTimeParseException e) {
                    //bad date in this row, skip it
                }
            }

            return latest;
        }
    }
}
