package com.example.RoTransit.service;

import com.example.RoTransit.repository.CityRepository;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedSourceRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.nio.file.attribute.PosixFilePermissions;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * FeedService.sweepOrphanFiles on real files in ./feeds (ids 990201..990203 and uniquely named .part files, all
 * deleted afterwards). "Now" is 1 Jan 2000 and the test files are backdated: every real file in ./feeds is newer
 * than that, so to the sweep it is "younger than an hour" and this test can never delete it.
 */
class FeedServiceSweepTest {

    private static final Instant NOW = Instant.parse("2000-01-01T12:00:00Z");
    private static final FileTime OLD = FileTime.from(NOW.minus(Duration.ofHours(2)));
    private static final FileTime YOUNG = FileTime.from(NOW.minus(Duration.ofMinutes(30)));
    private static final Path DIR = FeedService.FEEDS_ROOT.resolve("990201");
    private static final Path OTHER_DIR = FeedService.FEEDS_ROOT.resolve("990202");
    private static final Path LINKED_DIR = FeedService.FEEDS_ROOT.resolve("990203");

    private final FeedVersionRepository versions = mock(FeedVersionRepository.class);
    private final FeedService service = new FeedService(mock(FeedRepository.class), mock(CityRepository.class),
            mock(FeedSourceRepository.class), versions, mock(FeedVersionService.class),
            Clock.fixed(NOW, ZoneId.of("Europe/Bucharest")));
    private final List<Path> rootParts = new ArrayList<>();

    @TempDir
    Path outside;

    @BeforeEach
    @AfterEach
    void cleanUp() throws IOException {
        for (Path dir : List.of(DIR, OTHER_DIR)) {
            if (Files.exists(dir)) {
                Files.setPosixFilePermissions(dir, PosixFilePermissions.fromString("rwxr-xr-x"));
                try (Stream<Path> paths = Files.walk(dir)) {
                    for (Path p : paths.sorted(Comparator.reverseOrder()).toList()) {
                        Files.delete(p);
                    }
                }
            }
        }
        Files.deleteIfExists(LINKED_DIR);
        for (Path part : rootParts) {
            Files.deleteIfExists(part);
        }
    }

    private static Path file(Path dir, String name, FileTime modified) throws IOException {
        Files.createDirectories(dir);
        Path file = Files.writeString(dir.resolve(name), name);
        Files.setLastModifiedTime(file, modified);
        return file;
    }

    /** A .part file where FeedService really creates them: directly in feeds/. */
    private Path rootPart(FileTime modified) throws IOException {
        Path part = file(FeedService.FEEDS_ROOT, "990201-" + UUID.randomUUID() + ".zip.part", modified);
        rootParts.add(part);
        return part;
    }

    private void referenced(Path... files) {
        when(versions.findAllFilePaths()).thenReturn(Stream.of(files).map(Path::toString).toList());
    }

    @Test
    void anOldZipNoRowPointsAtIsDeletedAReferencedOneIsKept() throws Exception {
        Path kept = file(DIR, "kept.zip", OLD);
        Path orphan = file(DIR, "orphan.zip", OLD);
        referenced(kept);

        service.sweepOrphanFiles();

        assertThat(kept).exists();
        assertThat(orphan).doesNotExist();
    }

    @Test
    void aReferencedFileStoredAsAnAbsolutePathIsKeptToo() throws Exception {
        Path kept = file(DIR, "kept.zip", OLD);
        referenced(kept.toAbsolutePath());

        service.sweepOrphanFiles();

        assertThat(kept).exists();
    }

    @Test
    void aYoungOrphanZipIsKeptItMayBeADownloadBetweenMoveAndSave() throws Exception {
        Path young = file(DIR, "just-moved.zip", YOUNG);
        referenced();

        service.sweepOrphanFiles();

        assertThat(young).exists();
    }

    @Test
    void youngPartFilesAreKeptOldOnesAreDeletedInFeedsAndInTheSubfolders() throws Exception {
        Path youngRoot = rootPart(YOUNG);
        Path oldRoot = rootPart(OLD);
        Path oldInDir = file(DIR, "x.zip.part", OLD);
        Path youngInDir = file(DIR, "y.zip.part", YOUNG);
        referenced();

        service.sweepOrphanFiles();

        assertThat(youngRoot).as("a download in progress").exists();
        assertThat(oldRoot).doesNotExist();
        assertThat(oldInDir).doesNotExist();
        assertThat(youngInDir).exists();
    }

    @Test
    void aSymlinkedFeedFolderIsNotFollowed() throws Exception {
        Path target = file(outside, "outside.zip", OLD);
        Files.createSymbolicLink(LINKED_DIR, outside.toAbsolutePath());
        referenced();

        service.sweepOrphanFiles();

        assertThat(target).as("outside feeds/, must survive").exists();
        assertThat(LINKED_DIR).as("the link itself is left alone").isSymbolicLink();
    }

    @Test
    void aSymlinkInsideAFeedFolderIsLeftAlone() throws Exception {
        Path target = file(outside, "outside.zip", OLD);
        file(DIR, "kept.zip", OLD);
        Path link = Files.createSymbolicLink(DIR.resolve("link.zip"), target.toAbsolutePath());
        referenced(DIR.resolve("kept.zip"));

        service.sweepOrphanFiles();

        assertThat(target).exists();
        assertThat(link).isSymbolicLink();
    }

    @Test
    void aDatabaseErrorIsOnlyLoggedAndNothingIsDeleted() throws Exception {
        Path orphan = file(DIR, "orphan.zip", OLD);
        when(versions.findAllFilePaths()).thenThrow(new IllegalStateException("db down"));

        assertThatCode(service::sweepOrphanFiles).doesNotThrowAnyException();

        assertThat(orphan).as("without the list of used files, keeping everything is the safe choice").exists();
    }

    @Test
    void aFileThatCannotBeDeletedIsOnlyLoggedAndTheRestIsStillSwept() throws Exception {
        Path stuck = file(DIR, "stuck.zip", OLD);
        Path other = file(OTHER_DIR, "other.zip", OLD);
        Files.setPosixFilePermissions(DIR, PosixFilePermissions.fromString("r-xr-xr-x")); // can't delete inside
        referenced();

        assertThatCode(service::sweepOrphanFiles).doesNotThrowAnyException();

        assertThat(stuck).exists();
        assertThat(other).doesNotExist();
    }
}
