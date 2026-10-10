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
import java.nio.file.LinkOption;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Optional;
import java.util.stream.Stream;
import java.util.Set;
import java.util.HashSet;
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
    private final Clock clock;
    private final HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    public FeedService(FeedRepository feeds, CityRepository cities, FeedSourceRepository sources,
                       FeedVersionRepository versions, FeedVersionService versionService, Clock clock) {
        this.feeds = feeds;
        this.cities = cities;
        this.sources = sources;
        this.versions = versions;
        this.versionService = versionService;
        this.clock = clock;
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
     * Downloads the feed from its priority-1 source and stores a new file as feeds/{feedId}/{sha256}.zip.
     * The same file as the current or upcoming one is reported as unchanged and nothing is saved.
     * A new file becomes "upcoming" when its timetable starts after today and we have a current version to serve
     * until then; otherwise it becomes "current" right away.
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
        boolean upcoming;

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
            try (ZipFile check = new ZipFile(temp.toFile())) {} // throws if its not a valid zip
            catch (ZipException e) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                        "source sent an invalid zip for " + sourceUrl, e);
            }

            String sha256 = sha256(temp);
            FeedVersion current = versions.findByFeedIdAndStatus(id, FeedVersion.CURRENT).orElse(null);
            FeedVersion waiting = versions.findByFeedIdAndStatus(id, FeedVersion.UPCOMING).orElse(null);
            for (FeedVersion known : new FeedVersion[] {current, waiting}) {
                if (known != null && sha256.equals(known.getSha256()) && hasFile(known)) {
                    // the source has nothing new: keep everything as it is (finally deletes the temp file)
                    log.info("Feed {} is unchanged, the source sent the same file again", id);
                    markChecked(known);
                    return new DownloadResult(known, true);
                }
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
            // a timetable that starts later waits as "upcoming", but only if we have something to serve meanwhile:
            // a future feed is better than no feed at all
            LocalDate today = LocalDate.now(clock);
            upcoming = version.getStartsOn() != null && version.getStartsOn().isAfter(today) && current != null
                    && hasFile(current);

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
            saved = upcoming
                    ? versionService.saveAsUpcoming(version, operators)
                    : versionService.saveAsCurrent(version, operators);
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

    /** Remembers when the source last sent this file again, so the nightly job can skip it for a day. */
    private void markChecked(FeedVersion version) {
        Instant now = clock.instant();
        try {
            versions.markChecked(version.getId(), now);
            version.setCheckedAt(now);
        }
        catch (RuntimeException e) {
            // only an optimisation: the worst case is downloading the same file again tomorrow
            log.warn("Could not record the check of feed version {}", version.getId(), e);
        }
    }

    /**
     * How old a file must be before the sweep may delete it. A download in progress has a young .part file, and for a
     * moment after the move a young zip that no row points at yet; an hour is far longer than any download.
     */
    static final Duration SWEEP_MIN_AGE = Duration.ofHours(1);

    /**
     * Deletes leftovers of crashed downloads: .part temp files (they are created directly in feeds/) and zips in
     * feeds/{feedId}/ that no feed_version row points at. Only files older than SWEEP_MIN_AGE. Symlinks are never
     * followed or touched, so nothing outside feeds/ can be reached. Problems are only logged.
     */
    public void sweepOrphanFiles() {
        try {
            if (!Files.isDirectory(FEEDS_ROOT, LinkOption.NOFOLLOW_LINKS)) {
                return; // nothing downloaded yet
            }
            // compared as absolute paths, so "feeds/1/a.zip" and "/.../feeds/1/a.zip" count as the same file
            Set<Path> referenced = new HashSet<>();
            for (String filePath : versions.findAllFilePaths()) {
                referenced.add(Path.of(filePath).toAbsolutePath().normalize());
            }
            Instant cutoff = clock.instant().minus(SWEEP_MIN_AGE);
            for (Path path : list(FEEDS_ROOT)) {
                if (isPart(path)) {
                    deleteIfOlder(path, cutoff, "stale temp file");
                }
                else if (Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                        && path.getFileName().toString().matches("\\d+")) { // feeds/{feedId}/
                    for (Path file : list(path)) {
                        if (isPart(file)) {
                            deleteIfOlder(file, cutoff, "stale temp file");
                        }
                        else if (Files.isRegularFile(file, LinkOption.NOFOLLOW_LINKS)
                                && !referenced.contains(file.toAbsolutePath().normalize())) {
                            deleteIfOlder(file, cutoff, "orphan file");
                        }
                    }
                }
            }
        }
        catch (IOException | RuntimeException e) {
            log.warn("Sweeping orphan files in {} failed", FEEDS_ROOT, e);
        }
    }

    private static List<Path> list(Path dir) throws IOException {
        try (Stream<Path> paths = Files.list(dir)) {
            return paths.toList();
        }
    }

    /** A regular .part file (a symlink with that name is left alone). */
    private static boolean isPart(Path path) {
        return path.getFileName().toString().endsWith(".part") && Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS);
    }

    private static void deleteIfOlder(Path file, Instant cutoff, String what) {
        try {
            if (Files.getLastModifiedTime(file, LinkOption.NOFOLLOW_LINKS).toInstant().isBefore(cutoff)) {
                Files.delete(file);
                log.info("Sweep deleted {} {}", what, file);
            }
        }
        catch (IOException | RuntimeException e) {
            log.warn("Sweep could not delete {}", file, e); // the next sweep tries again
        }
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

    /**
     * Makes the feed's upcoming version current now (used on its start date, or by an admin who doesn't want to wait),
     * then cleans up files the switch made unnecessary. Empty if there is no upcoming version.
     */
    public Optional<FeedVersion> promoteUpcoming(Long feedId) {
        Optional<FeedVersion> promoted = versionService.promoteUpcoming(feedId);
        if (promoted.isPresent()) {
            log.info("Feed {} switched to the version starting {}", feedId, promoted.get().getStartsOn());
            deleteOldFiles(feedId);
        }
        return promoted;
    }

    /**
     * Retention: keeps the files of the current and upcoming versions and of the most recently served old one (the
     * version to go back to). Every other file is deleted and its file_path cleared; the rows stay as history.
     * An old version that was never served (an upcoming one replaced by a newer upcoming) gets no slot.
     * Problems are only logged: cleaning up must never fail a download.
     */
    void deleteOldFiles(Long feedId) {
        try {
            List<FeedVersion> successful = versions.findByFeedIdAndStatusInOrderByIdDesc(feedId,
                    List.of(FeedVersion.CURRENT, FeedVersion.UPCOMING, FeedVersion.OLD));
            FeedVersion lastServedOld = successful.stream()
                    .filter(v -> FeedVersion.OLD.equals(v.getStatus()) && v.getServedFrom() != null)
                    .max(java.util.Comparator.comparing(FeedVersion::getServedFrom))
                    .orElse(null);
            List<FeedVersion> kept = new ArrayList<>();
            List<FeedVersion> toClean = new ArrayList<>();
            for (FeedVersion v : successful) {
                if (!FeedVersion.OLD.equals(v.getStatus()) || v == lastServedOld) {
                    kept.add(v);
                }
                else {
                    toClean.add(v);
                }
            }
            List<String> keptPaths = kept.stream().map(FeedVersion::getFilePath).toList();

            for (FeedVersion old : toClean) {
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
