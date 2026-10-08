package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import org.apache.commons.csv.CSVException;
import org.apache.commons.csv.CSVFormat;
import org.apache.commons.csv.CSVParser;
import org.apache.commons.csv.CSVRecord;
import org.apache.commons.csv.DuplicateHeaderMode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.UncheckedIOException;
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
import java.util.zip.ZipException;

@Service
public class FeedService {
    public static final Path FEEDS_ROOT = Path.of("feeds");
    private static final Logger log = LoggerFactory.getLogger(FeedService.class);

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
            // TODO: a new feed may only start service in the future (e.g. a timetable change next week).
            // Read its earliest start date (feed_info.txt feed_start_date, else calendar.txt start_date);
            // if it is after today, keep the current zip and store this one as the upcoming feed
            // (e.g. feeds/{id}-next.zip with a starts_on column) and let FeedUpdateJob promote it on that date.
            // Belongs with the multi-operator DB redesign; meanwhile consider a log.warn
            // when the new feed starts after today.
            try (ZipFile check = new ZipFile(temp.toFile())) {} // throws if its not a valid zip
            catch (ZipException e) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                        "source sent an invalid zip for " + sourceUrl, e);
            }
            Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException | InterruptedException | RuntimeException e) {
            feed.setStatus("failed");
            feeds.save(feed);
            if (e instanceof InterruptedException) {
                // catching InterruptedException clears the thread's interrupt flag, so set it again for the caller
                Thread.currentThread().interrupt();
            }
            throw e;
        } finally {
            // after a successful move the temp file is gone, so this only cleans up failures
            Files.deleteIfExists(temp);
        }

        feed.setLocalPath(file.toString());
        feed.setStatus("downloaded");
        feed.setSourceUrl(sourceUrl);
        feed.setDownloadedAt(Instant.now());

        try {
            feed.setExpiresOn(readExpireDate(file));
        }
        catch (IOException | IllegalStateException e) {
            log.warn("Could not read expiry date for feed {}", id, e);
            feed.setExpiresOn(null);
        }

        return feeds.save(feed);
    }

    public LocalDate getExpireDate(Long id) throws IOException {
        Feed feed = feeds.findById(id).orElseThrow();
        return readExpireDate(Path.of(feed.getLocalPath()));
    }

    public LocalDate readExpireDate(Path file) throws IOException {
        try (ZipFile zip = new ZipFile(file.toFile())){
            LocalDate date = latestDate(zip, "feed_info.txt", "feed_end_date");
            if (date == null) date = latestDate(zip, "calendar.txt", "end_date");
            if (date == null) date = latestDate(zip, "calendar_dates.txt", "date");
            if (date == null) throw new IllegalStateException("no expiry date found in " + file);
            return date;
        }
    }

    private LocalDate latestDate (ZipFile zip, String fileName, String column) throws IOException {
        ZipEntry entry = zip.getEntry(fileName);
        if (entry == null) {
            return null;
        }
        CSVFormat format = CSVFormat.DEFAULT.builder()
                .setHeader()
                .setSkipHeaderRecord(true)
                .setIgnoreSurroundingSpaces(true)
                .setIgnoreEmptyLines(true)
                .setTrim(true)
                .setAllowMissingColumnNames(true) // trailing commas give an empty header name
                .setDuplicateHeaderMode(DuplicateHeaderMode.ALLOW_ALL)
                .get();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(zip.getInputStream(entry), StandardCharsets.UTF_8))) {
            // skip a UTF-8 BOM at the start, otherwise the first header name would not match
            reader.mark(1);
            if (reader.read() != '\uFEFF') {
                reader.reset();
            }

            try (CSVParser parser = format.parse(reader)) {
                LocalDate latest = null;
                for (CSVRecord record : parser) {
                    if (!record.isSet(column)) {
                        continue; // column missing in the header, or a short row
                    }
                    String value = record.get(column);
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
            catch (UncheckedIOException e) {
                // the parser wraps errors from inside the rows in this; unwrap so the catch below can see a CSVException
                throw e.getCause();
            }
        }
        catch (CSVException e) {
            // broken CSV in this file (e.g. an unclosed quote): skip it so readExpireDate can try the next file
            log.warn("Could not parse {} in {}, skipping it", fileName, zip.getName(), e);
            return null;
        }
    }
}
