package com.example.RoTransit.service;

import com.example.RoTransit.entity.City;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedSource;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.entity.Operator;
import com.example.RoTransit.repository.CityRepository;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedSourceRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import org.apache.commons.csv.CSVException;
import org.apache.commons.csv.CSVFormat;
import org.apache.commons.csv.CSVParser;
import org.apache.commons.csv.CSVRecord;
import org.apache.commons.csv.DuplicateHeaderMode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipException;

@Service
public class FeedService {
    public static final Path FEEDS_ROOT = Path.of("feeds");
    private static final Logger log = LoggerFactory.getLogger(FeedService.class);

    // how we read every GTFS csv file: first row is the header, values trimmed, quotes handled by the parser
    private static final CSVFormat GTFS_CSV = CSVFormat.DEFAULT.builder()
            .setHeader()
            .setSkipHeaderRecord(true)
            .setIgnoreSurroundingSpaces(true)
            .setIgnoreEmptyLines(true)
            .setTrim(true)
            .setAllowMissingColumnNames(true) // trailing commas give an empty header name
            .setDuplicateHeaderMode(DuplicateHeaderMode.ALLOW_ALL)
            .get();

    private final FeedRepository feeds;
    private final CityRepository cities;
    private final FeedSourceRepository sources;
    private final FeedVersionRepository versions;
    private final FeedVersionService versionService;
    private final HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    public FeedService(FeedRepository feeds, CityRepository cities, FeedSourceRepository sources,
                       FeedVersionRepository versions, FeedVersionService versionService) {
        this.feeds = feeds;
        this.cities = cities;
        this.sources = sources;
        this.versions = versions;
        this.versionService = versionService;
    }

    /** Creates the city (only if it doesn't exist yet), the feed and its priority-1 source: all three or none. */
    @Transactional
    public Feed createFeed(String cityName, String feedName, String sourceRef) {
        City city = cities.findByName(cityName).orElseGet(() -> {
            City newCity = new City();
            newCity.setName(cityName);
            return cities.save(newCity);
        });

        Feed feed = new Feed();
        feed.setCity(city);
        feed.setName(feedName);
        feed = feeds.save(feed);

        FeedSource source = new FeedSource();
        source.setFeed(feed);
        source.setKind(FeedSource.MOBILITYDB);
        source.setRef(sourceRef);
        source.setPriority(1);
        sources.save(source);

        return feed;
    }

    /**
     * Downloads the feed from its priority-1 source. A new file becomes the current version, stored as
     * feeds/{feedId}/{sha256}.zip; the same file as the current one is reported as unchanged and nothing is saved.
     * Any failure is stored as a "failed" version and rethrown; the current version and its file stay as they were.
     */
    public DownloadResult download(Long id) throws IOException, InterruptedException {
        Feed feed = feeds.findById(id).orElseThrow();
        // step 1 of the redesign: one source per feed (falling back to other sources comes in step 2)
        FeedSource source = sources.findByFeedIdAndPriority(id, 1).orElse(null);
        Instant attemptedAt = Instant.now();
        FeedVersion version = new FeedVersion();
        List<Operator> operators;
        Path file;

        Path temp = null;
        try {
            if (source == null) {
                throw new IllegalStateException("feed " + id + " has no source with priority 1");
            }
            String sourceUrl = source.downloadUrl();
            Files.createDirectories(FEEDS_ROOT);

            HttpRequest request = HttpRequest.newBuilder(URI.create(sourceUrl)).GET().build();
            temp = Files.createFile(FEEDS_ROOT.resolve(id + "-" + UUID.randomUUID() + ".zip.part"));
            HttpResponse<Path> response = client.send(request, HttpResponse.BodyHandlers.ofFile(temp));

            if (response.statusCode() != 200) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                        "source returned " + response.statusCode() + " for " + sourceUrl);
            }
            // TODO (step 3): a new feed may only start service in the future (e.g. a timetable change next week).
            // starts_on is stored now; when it is after today, keep serving the current version, store this one as
            // "upcoming" and let FeedUpdateJob promote it on that date.
            try (ZipFile check = new ZipFile(temp.toFile())) {} // throws if its not a valid zip
            catch (ZipException e) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                        "source sent an invalid zip for " + sourceUrl, e);
            }

            String sha256 = sha256(temp);
            FeedVersion current = versions.findByFeedIdAndStatus(id, FeedVersion.CURRENT).orElse(null);
            if (current != null && sha256.equals(current.getSha256()) && hasFile(current)) {
                // the source has nothing new: keep everything as it is (finally deletes the temp file)
                log.info("Feed {} is unchanged, the source sent the same file again", id);
                return new DownloadResult(current, true);
            }

            // read what we store about the new file before moving it
            version.setSha256(sha256);
            try {
                version.setExpiresOn(readExpireDate(temp));
            }
            catch (IOException | IllegalStateException e) {
                log.warn("Could not read expiry date for feed {}", id, e);
            }
            version.setStartsOn(readStartDate(temp));
            operators = readOperators(temp);

            // named after the content, not the version id: the id only exists after the row is saved,
            // and we want the file in place before the row says it is there
            file = FEEDS_ROOT.resolve(id.toString()).resolve(sha256 + ".zip");
            Files.createDirectories(file.getParent());
            // REPLACE_EXISTING: the file may already be there if the feed went back to an older file (A -> B -> A);
            // same name means same content, so replacing it changes nothing
            Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException | InterruptedException | RuntimeException e) {
            versionService.saveFailed(feed, source, attemptedAt);
            if (e instanceof InterruptedException) {
                // catching InterruptedException clears the thread's interrupt flag, so set it again for the caller
                Thread.currentThread().interrupt();
            }
            throw e;
        } finally {
            // after a successful move the temp file is gone, so this only cleans up failures and unchanged files
            if (temp != null) {
                Files.deleteIfExists(temp);
            }
        }

        version.setFeed(feed);
        version.setSource(source);
        version.setFilePath(file.toString());
        version.setDownloadedAt(Instant.now());
        FeedVersion saved;
        try {
            saved = versionService.saveAsCurrent(version, operators);
        }
        catch (RuntimeException e) {
            // the transaction was rolled back, so no row points at the file we just moved: remove it so disk and
            // database don't drift apart, then record the failure like any other
            deleteIfUnused(file);
            try {
                versionService.saveFailed(feed, source, attemptedAt);
            }
            catch (RuntimeException saveError) {
                e.addSuppressed(saveError); // the database is probably down; report the original error
            }
            throw e;
        }
        deleteOldFiles(id);
        return new DownloadResult(saved, false);
    }

    private static boolean hasFile(FeedVersion version) {
        return version.getFilePath() != null && Files.isRegularFile(Path.of(version.getFilePath()));
    }

    /** Deletes a file unless some version row still points at it (e.g. an old version with the same content). */
    private void deleteIfUnused(Path file) {
        try {
            if (!versions.existsByFilePath(file.toString())) {
                Files.deleteIfExists(file);
            }
        }
        catch (IOException | RuntimeException e) {
            // if we can't even check, keeping the file is the safe choice
            log.warn("Could not clean up {}", file, e);
        }
    }

    /** How many successful versions keep their file: the current one plus one old one to go back to. */
    static final int VERSIONS_WITH_FILES = 2;

    /**
     * Retention: deletes the files of successful versions older than the newest VERSIONS_WITH_FILES and clears their
     * file_path. The rows stay as history. Problems are only logged: cleaning up must never fail a download.
     */
    void deleteOldFiles(Long feedId) {
        try {
            List<FeedVersion> successful = versions.findByFeedIdAndStatusInOrderByIdDesc(feedId,
                    List.of(FeedVersion.CURRENT, FeedVersion.OLD));
            List<FeedVersion> kept = successful.subList(0, Math.min(VERSIONS_WITH_FILES, successful.size()));
            List<String> keptPaths = kept.stream().map(FeedVersion::getFilePath).toList();

            for (FeedVersion old : successful.subList(kept.size(), successful.size())) {
                String path = old.getFilePath();
                if (path == null) {
                    continue; // cleaned up before
                }
                try {
                    // the same content gives the same file name, so an old version can share a kept version's file
                    if (!keptPaths.contains(path)) {
                        Files.deleteIfExists(Path.of(path));
                    }
                    old.setFilePath(null);
                    versions.save(old);
                }
                catch (IOException | RuntimeException e) {
                    // file_path stays set, so the next successful download tries again
                    log.warn("Could not delete old file {} of feed {}", path, feedId, e);
                }
            }
        }
        catch (RuntimeException e) {
            log.warn("Could not clean up old files of feed {}", feedId, e);
        }
    }

    /** Expiry date of the feed's current file. 404 if the feed has never been downloaded. */
    public LocalDate getExpireDate(Long id) throws IOException {
        feeds.findById(id).orElseThrow(); // unknown id -> NoSuchElementException -> 404 "Feed not found"
        FeedVersion current = versions.findByFeedIdAndStatus(id, FeedVersion.CURRENT)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "feed has no current version"));
        return readExpireDate(Path.of(current.getFilePath()));
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

    /** First day of service, same fallback order as readExpireDate. Null (with a warning) when it can't be read. */
    private LocalDate readStartDate(Path file) {
        try (ZipFile zip = new ZipFile(file.toFile())) {
            LocalDate date = earliestDate(zip, "feed_info.txt", "feed_start_date");
            if (date == null) date = earliestDate(zip, "calendar.txt", "start_date");
            if (date == null) date = earliestDate(zip, "calendar_dates.txt", "date");
            return date;
        }
        catch (IOException e) {
            log.warn("Could not read start date from {}", file, e);
            return null;
        }
    }

    private LocalDate latestDate (ZipFile zip, String fileName, String column) throws IOException {
        return findDate(zip, fileName, column, true);
    }

    private LocalDate earliestDate (ZipFile zip, String fileName, String column) throws IOException {
        return findDate(zip, fileName, column, false);
    }

    /** The latest (or earliest) yyyyMMdd date in one column of one file; null if the file or column has none. */
    private LocalDate findDate (ZipFile zip, String fileName, String column, boolean latest) throws IOException {
        ZipEntry entry = zip.getEntry(fileName);
        if (entry == null) {
            return null;
        }
        try {
            try (CSVParser parser = openCsv(zip, entry)) {
                LocalDate found = null;
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
                        if (found == null || (latest ? d.isAfter(found) : d.isBefore(found))) {
                            found = d;
                        }
                    }
                    catch (DateTimeParseException e) {
                        //bad date in this row, skip it
                    }
                }
                return found;
            }
            catch (UncheckedIOException e) {
                // the parser wraps errors from inside the rows in this; unwrap so the catch below can see a CSVException
                throw e.getCause();
            }
        }
        catch (CSVException e) {
            // broken CSV in this file (e.g. an unclosed quote): skip it so the caller can try the next file
            log.warn("Could not parse {} in {}, skipping it", fileName, zip.getName(), e);
            return null;
        }
    }

    /** Reads agency.txt into Operator rows. A missing or broken agency.txt is not an error: we store no operators. */
    private List<Operator> readOperators(Path file) {
        List<Operator> operators = new ArrayList<>();
        try (ZipFile zip = new ZipFile(file.toFile())) {
            ZipEntry entry = zip.getEntry("agency.txt");
            if (entry == null) {
                log.warn("No agency.txt in {}, storing no operators", file);
                return operators;
            }
            try (CSVParser parser = openCsv(zip, entry)) {
                for (CSVRecord record : parser) {
                    String name = valueOf(record, "agency_name");
                    if (name == null) {
                        continue; // agency_name is required by GTFS, a row without it is useless
                    }
                    Operator operator = new Operator();
                    operator.setAgencyId(valueOf(record, "agency_id"));
                    operator.setName(name);
                    operator.setUrl(valueOf(record, "agency_url"));
                    operators.add(operator);
                }
            }
        }
        catch (IOException | UncheckedIOException e) {
            // CSVException (broken csv) is an IOException too; the parser wraps errors in later rows as unchecked
            log.warn("Could not read agency.txt in {}, storing no operators", file, e);
            return new ArrayList<>(); // drop rows read before the error, all or nothing
        }
        return operators;
    }

    /** The value of a column, or null when the column is missing, the row is too short, or the value is empty. */
    private static String valueOf(CSVRecord record, String column) {
        if (!record.isSet(column) || record.get(column).isEmpty()) {
            return null;
        }
        return record.get(column);
    }

    /** Opens one csv file of the zip. A UTF-8 BOM at the start is skipped, otherwise the first header name would not match. */
    private static CSVParser openCsv(ZipFile zip, ZipEntry entry) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(zip.getInputStream(entry), StandardCharsets.UTF_8));
        reader.mark(1);
        if (reader.read() != '\uFEFF') {
            reader.reset();
        }
        try {
            return GTFS_CSV.parse(reader); // closing the parser closes the reader too
        }
        catch (IOException e) {
            reader.close(); // e.g. a broken header: nothing will close the reader for us
            throw e;
        }
    }

    /** SHA-256 of a file as 64 hex characters, so we can tell later whether two downloads are the same file. */
    private static String sha256(Path file) throws IOException {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream in = new DigestInputStream(Files.newInputStream(file), digest)) {
                in.transferTo(OutputStream.nullOutputStream()); // reading the stream feeds the digest
            }
            return HexFormat.of().formatHex(digest.digest());
        }
        catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is not available", e); // every Java has it, so this never happens
        }
    }
}
