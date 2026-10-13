package com.example.RoTransit.service;

import com.example.RoTransit.TestEntities;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.repository.CityRepository;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedSourceRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Retention (FeedService.deleteOldFiles): current, upcoming and the most recently served old version keep their files. Real files in
 * ./feeds/990101/ (deleted afterwards), mocked repository.
 */
class FeedServiceRetentionTest {

    private static final long ID = 990101L;
    private static final Path DIR = FeedService.FEEDS_ROOT.resolve(String.valueOf(ID));

    private final FeedVersionRepository versions = mock(FeedVersionRepository.class);
    private final FeedService service = new FeedService(mock(FeedRepository.class), mock(CityRepository.class),
            mock(FeedSourceRepository.class), versions, mock(FeedVersionService.class),
            TestEntities.CLOCK);
    private final Feed feed = TestEntities.feed(ID, "Testville", "TestCo");

    @BeforeEach
    @AfterEach
    void cleanUp() throws IOException {
        if (Files.exists(DIR)) {
            try (Stream<Path> paths = Files.walk(DIR)) {
                for (Path p : paths.sorted(Comparator.reverseOrder()).toList()) {
                    Files.delete(p);
                }
            }
        }
    }

    private Path file(String name) throws IOException {
        Files.createDirectories(DIR);
        return Files.writeString(DIR.resolve(name), name);
    }

    /** Current and old versions were served (in id order: a higher id was served later); upcoming ones not yet. */
    private FeedVersion version(long id, String status, Path file) {
        FeedVersion v = TestEntities.version(id, feed, status, file == null ? null : file.toString(), null);
        if (!FeedVersion.UPCOMING.equals(status)) {
            v.setServedFrom(java.time.Instant.parse("2026-01-01T00:00:00Z").plusSeconds(id * 86400));
        }
        return v;
    }

    /** An old version that was never current: an upcoming one that a newer upcoming replaced. */
    private FeedVersion neverServed(long id, Path file) {
        return TestEntities.version(id, feed, FeedVersion.OLD, file.toString(), null);
    }

    /** What the repository returns: successful versions, newest first. */
    private void successful(FeedVersion... newestFirst) {
        when(versions.findByFeedIdAndStatusInOrderByIdDesc(ID, List.of(FeedVersion.CURRENT, FeedVersion.UPCOMING, FeedVersion.OLD)))
                .thenReturn(List.of(newestFirst));
    }

    @Test
    void onlyTheNewestTwoKeepTheirFilesOlderRowsKeepTheirRowButLoseTheirPath() throws Exception {
        Path f5 = file("e.zip"), f4 = file("d.zip"), f3 = file("c.zip"), f2 = file("b.zip");
        FeedVersion v5 = version(5, FeedVersion.CURRENT, f5);
        FeedVersion v4 = version(4, FeedVersion.OLD, f4);
        FeedVersion v3 = version(3, FeedVersion.OLD, f3);
        FeedVersion v2 = version(2, FeedVersion.OLD, f2);
        FeedVersion v1 = version(1, FeedVersion.OLD, null); // cleaned up by an earlier run
        successful(v5, v4, v3, v2, v1);

        service.deleteOldFiles(ID);

        assertThat(f5).exists();
        assertThat(f4).exists();
        assertThat(f3).doesNotExist();
        assertThat(f2).doesNotExist();
        assertThat(v5.getFilePath()).isEqualTo(f5.toString());
        assertThat(v4.getFilePath()).isEqualTo(f4.toString());
        assertThat(v3.getFilePath()).isNull();
        assertThat(v2.getFilePath()).isNull();
        // rows are kept (only updated, never deleted), and nothing to do for v1
        verify(versions).save(v3);
        verify(versions).save(v2);
        verify(versions, never()).save(v1);
        verify(versions, never()).save(v5);
        verify(versions, never()).save(v4);
        verify(versions, never()).delete(any());
        verify(versions, never()).deleteById(anyLong());
    }

    @Test
    void aFileStillUsedByAKeptVersionIsNeverDeleted() throws Exception {
        // A -> B -> A: the old A row (v1) shares its file with the current A row (v3)
        Path fileA = file("a.zip"), fileB = file("b.zip");
        FeedVersion v3 = version(3, FeedVersion.CURRENT, fileA);
        FeedVersion v2 = version(2, FeedVersion.OLD, fileB);
        FeedVersion v1 = version(1, FeedVersion.OLD, fileA);
        successful(v3, v2, v1);

        service.deleteOldFiles(ID);

        assertThat(fileA).hasContent("a.zip");
        assertThat(fileB).exists();
        assertThat(v1.getFilePath()).as("the old row no longer claims the file").isNull();
        assertThat(v3.getFilePath()).isEqualTo(fileA.toString());
        verify(versions).save(v1);
    }

    @Test
    void aDeleteFailureIsOnlyLoggedKeepsThePathAndTheRestIsStillCleanedUp() throws Exception {
        Path f4 = file("d.zip"), f3 = file("c.zip"), f1 = file("a.zip");
        Path stuck = Files.createDirectories(DIR.resolve("stuck.zip")); // a non-empty folder can't be deleted
        Files.writeString(stuck.resolve("inside"), "x");
        FeedVersion v4 = version(4, FeedVersion.CURRENT, f4);
        FeedVersion v3 = version(3, FeedVersion.OLD, f3);
        FeedVersion v2 = version(2, FeedVersion.OLD, stuck);
        FeedVersion v1 = version(1, FeedVersion.OLD, f1);
        successful(v4, v3, v2, v1);

        assertThatCode(() -> service.deleteOldFiles(ID)).doesNotThrowAnyException();

        assertThat(stuck).exists();
        assertThat(v2.getFilePath()).as("kept, so the next run tries again").isEqualTo(stuck.toString());
        verify(versions, never()).save(v2);
        assertThat(f1).doesNotExist();
        assertThat(v1.getFilePath()).isNull();
    }

    @Test
    void aFileThatIsAlreadyGoneJustClearsThePath() {
        FeedVersion v3 = version(3, FeedVersion.CURRENT, DIR.resolve("c.zip"));
        FeedVersion v2 = version(2, FeedVersion.OLD, DIR.resolve("b.zip"));
        FeedVersion v1 = version(1, FeedVersion.OLD, DIR.resolve("gone.zip"));
        successful(v3, v2, v1);

        service.deleteOldFiles(ID);

        assertThat(v1.getFilePath()).isNull();
        verify(versions).save(v1);
    }

    @Test
    void twoOrFewerVersionsMeansNothingToDo() throws Exception {
        Path f2 = file("b.zip"), f1 = file("a.zip");
        successful(version(2, FeedVersion.CURRENT, f2), version(1, FeedVersion.OLD, f1));

        service.deleteOldFiles(ID);

        assertThat(f2).exists();
        assertThat(f1).exists();
        verify(versions, never()).save(any());
    }

    @Test
    void aDatabaseErrorIsOnlyLogged() {
        when(versions.findByFeedIdAndStatusInOrderByIdDesc(anyLong(), any())).thenThrow(new IllegalStateException("db down"));

        assertThatCode(() -> service.deleteOldFiles(ID)).doesNotThrowAnyException();
    }

    @Test
    void currentUpcomingAndTheNewestOldKeepTheirFilesEverythingOlderLosesIt() throws Exception {
        Path f4 = file("up.zip"), f3 = file("cur.zip"), f2 = file("old-new.zip"), f1 = file("old-older.zip");
        // ids newest first: upcoming (4) was downloaded after current (3), which replaced 2, which replaced 1
        FeedVersion v4 = version(4, FeedVersion.UPCOMING, f4);
        FeedVersion v3 = version(3, FeedVersion.CURRENT, f3);
        FeedVersion v2 = version(2, FeedVersion.OLD, f2);
        FeedVersion v1 = version(1, FeedVersion.OLD, f1);
        successful(v4, v3, v2, v1);

        service.deleteOldFiles(ID);

        assertThat(f4).exists();
        assertThat(f3).exists();
        assertThat(f2).as("one old version to go back to").exists();
        assertThat(f1).doesNotExist();
        assertThat(v1.getFilePath()).isNull();
        assertThat(v4.getFilePath()).isEqualTo(f4.toString());
        assertThat(v2.getFilePath()).isEqualTo(f2.toString());
        verify(versions).save(v1);
        verify(versions, never()).save(v2);
        verify(versions, never()).save(v3);
        verify(versions, never()).save(v4);
    }

    @Test
    void anOldVersionSharingTheUpcomingFileKeepsTheFileOnDisk() throws Exception {
        // A (old, 1) -> B (old, 2) -> C (current, 3) -> upcoming is A again (4): same content, same file
        Path a = file("a.zip"), b = file("b.zip"), c = file("c.zip");
        FeedVersion v4 = version(4, FeedVersion.UPCOMING, a);
        FeedVersion v3 = version(3, FeedVersion.CURRENT, c);
        FeedVersion v2 = version(2, FeedVersion.OLD, b);
        FeedVersion v1 = version(1, FeedVersion.OLD, a);
        successful(v4, v3, v2, v1);

        service.deleteOldFiles(ID);

        assertThat(a).as("the upcoming version still uses it").exists();
        assertThat(v1.getFilePath()).isNull();
        assertThat(b).exists();
    }

    @Test
    void anUpcomingReplacedBeforeBeingServedLosesItsFileAndTheLastServedOldKeepsIt() throws Exception {
        // 1 was current, then 2 became current (1 -> old); 3 arrived as upcoming, then 4 replaced it (3 -> old)
        Path f4 = file("up-new.zip"), f3 = file("up-replaced.zip"), f2 = file("cur.zip"), f1 = file("served-old.zip");
        FeedVersion v4 = version(4, FeedVersion.UPCOMING, f4);
        FeedVersion v3 = neverServed(3, f3);
        FeedVersion v2 = version(2, FeedVersion.CURRENT, f2);
        FeedVersion v1 = version(1, FeedVersion.OLD, f1);
        successful(v4, v3, v2, v1);

        service.deleteOldFiles(ID);

        assertThat(f3).as("never served: no slot, even though it is the newest old row").doesNotExist();
        assertThat(v3.getFilePath()).isNull();
        assertThat(f1).as("the version to go back to").exists();
        assertThat(v1.getFilePath()).isEqualTo(f1.toString());
        assertThat(f2).exists();
        assertThat(f4).exists();
        verify(versions).save(v3);
        verify(versions, never()).save(v1);
    }

    @Test
    void theOldSlotGoesToTheMostRecentlyServedNotTheHighestId() throws Exception {
        // served order differs from id order: 2 was served after 3 (e.g. an admin went back to it)
        Path f4 = file("cur.zip"), f3 = file("three.zip"), f2 = file("two.zip");
        FeedVersion v4 = version(4, FeedVersion.CURRENT, f4);
        FeedVersion v3 = version(3, FeedVersion.OLD, f3);
        FeedVersion v2 = version(2, FeedVersion.OLD, f2);
        v2.setServedFrom(v3.getServedFrom().plusSeconds(60));
        successful(v4, v3, v2);

        service.deleteOldFiles(ID);

        assertThat(f2).exists();
        assertThat(f3).doesNotExist();
    }

    @Test
    void aNeverServedOldSharingAKeptFileLeavesTheFileOnDisk() throws Exception {
        Path shared = file("shared.zip"), f1 = file("served-old.zip");
        FeedVersion v3 = version(3, FeedVersion.CURRENT, shared);
        FeedVersion v2 = neverServed(2, shared); // same content as the current one
        FeedVersion v1 = version(1, FeedVersion.OLD, f1);
        successful(v3, v2, v1);

        service.deleteOldFiles(ID);

        assertThat(shared).as("the current version still uses it").exists();
        assertThat(v2.getFilePath()).isNull();
        assertThat(f1).exists();
    }

    @Test
    void withOnlyNeverServedOldVersionsNoOldFileIsKept() throws Exception {
        Path f2 = file("cur.zip"), f1 = file("replaced-upcoming.zip");
        FeedVersion v2 = version(2, FeedVersion.CURRENT, f2);
        FeedVersion v1 = neverServed(1, f1);
        successful(v2, v1);

        service.deleteOldFiles(ID);

        assertThat(f1).doesNotExist();
        assertThat(f2).exists();
    }
}
