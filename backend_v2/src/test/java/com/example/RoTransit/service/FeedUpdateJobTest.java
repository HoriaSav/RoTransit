package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

import static com.example.RoTransit.TestEntities.current;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

/**
 * FeedUpdateJob with mocked repositories/service. The job decides from the current version's expiresOn (and whether
 * its file exists); it must never open the zip itself (no getExpireDate/readExpireDate calls) and never saves
 * anything itself: FeedService.download stores successes and failures.
 * The job uses LocalDate.now() directly, so dates here are relative to LocalDate.now().
 */
class FeedUpdateJobTest {

    private final FeedRepository repo = mock(FeedRepository.class);
    private final FeedVersionRepository versions = mock(FeedVersionRepository.class);
    private final FeedService service = mock(FeedService.class);
    private final FeedUpdateJob job = new FeedUpdateJob(repo, versions, service);

    /** Current version of each feed, as findCurrentByFeedId() returns it. */
    private final Map<Long, FeedVersion> currentVersions = new HashMap<>();

    @TempDir
    Path tmp;

    /** By default every download brings a new file; tests that need "unchanged" or a failure stub their own. */
    @org.junit.jupiter.api.BeforeEach
    void downloadsAreNewByDefault() throws Exception {
        when(service.download(anyLong())).thenAnswer(inv -> new DownloadResult(
                current(com.example.RoTransit.TestEntities.feed(inv.getArgument(0), "X", "XCo"), "feeds/x.zip", null),
                false));
    }

    /** Guard: an interrupt test must never leak the flag into the next test, even when it fails half-way. */
    @AfterEach
    void clearInterruptFlag() {
        Thread.interrupted();
    }

    private Path existingZip() throws IOException {
        return Files.createFile(tmp.resolve("present-" + System.nanoTime() + ".zip"));
    }

    /** A feed whose current version has this file path and expiry date. */
    private Feed feed(long id, String city, String filePath, LocalDate expiresOn) {
        Feed feed = com.example.RoTransit.TestEntities.feed(id, city, city + "Co");
        currentVersions.put(id, current(feed, filePath, expiresOn));
        return feed;
    }

    private List<String> run(Feed... feeds) {
        stubFeeds(feeds);
        List<String> lines = new ArrayList<>();
        job.updateFeeds(lines::add);
        return lines;
    }

    private void stubFeeds(Feed... feeds) {
        when(repo.findAll()).thenReturn(List.of(feeds));
        when(versions.findCurrentByFeedId()).thenReturn(currentVersions);
    }

    private void verifyZipNeverRead() throws IOException {
        verify(service, never()).getExpireDate(any());
        verify(service, never()).readExpireDate(any());
    }

    /** The job only reads; it must never write feeds or versions itself. */
    private void verifyJobSavedNothing() {
        verify(repo, never()).save(any());
        verify(versions, never()).save(any());
        verify(versions, never()).markCurrentAsOld(anyLong());
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   ", "/definitely/not/here/feed.zip"})
    void missingLocalFileDownloadsEvenWhenExpiryIsFarAway(String filePath) throws Exception {
        List<String> lines = run(feed(1, "NoFile", filePath, LocalDate.now().plusYears(1)));

        assertThat(lines).containsExactly("NoFile has been updated!");
        verify(service, times(1)).download(1L);
        verifyZipNeverRead();
    }

    @Test
    void feedWithoutAnyCurrentVersionDownloads() throws Exception {
        Feed neverDownloaded = com.example.RoTransit.TestEntities.feed(1, "New", "NewCo"); // not in currentVersions

        List<String> lines = run(neverDownloaded);

        assertThat(lines).containsExactly("New has been updated!");
        verify(service, times(1)).download(1L);
    }

    @Test
    void nullExpiresOnDownloadsEvenWhenTheFileExists() throws Exception {
        List<String> lines = run(feed(1, "NoExpiry", existingZip().toString(), null));

        assertThat(lines).containsExactly("NoExpiry has been updated!");
        verify(service, times(1)).download(1L);
        verifyZipNeverRead();
    }

    @ParameterizedTest
    @ValueSource(ints = {-30, -1, 0, 1, 6})
    void expiryBeforeTodayPlusSevenDownloads(int daysFromToday) throws Exception {
        List<String> lines = run(feed(1, "Soon", existingZip().toString(), LocalDate.now().plusDays(daysFromToday)));

        assertThat(lines).containsExactly("Soon has been updated!");
        verify(service, times(1)).download(1L);
        verifyZipNeverRead();
    }

    @Test
    void expiryExactlySevenDaysAheadIsStillUpToDate() throws Exception {
        // boundary as implemented: expires.isBefore(today + 7), so today + 7 does NOT trigger a download
        List<String> lines = run(feed(1, "Boundary", existingZip().toString(), LocalDate.now().plusDays(7)));

        assertThat(lines).containsExactly("Boundary is up to date!");
        verify(service, never()).download(anyLong());
    }

    @Test
    void farFutureExpiryIsUpToDateWithoutDownloadingOrReadingTheZip() throws Exception {
        List<String> lines = run(feed(1, "Fresh", existingZip().toString(), LocalDate.now().plusDays(30)));

        assertThat(lines).containsExactly("Fresh is up to date!");
        verify(service, never()).download(anyLong());
        verifyZipNeverRead();
        verifyJobSavedNothing();
    }

    @Test
    void currentVersionsAreLoadedOnceForTheWholeRun() throws Exception {
        String present = existingZip().toString();
        run(feed(1, "A", present, LocalDate.now().plusDays(30)), feed(2, "B", present, LocalDate.now().plusDays(30)));

        verify(versions, times(1)).findCurrentByFeedId();
        verify(versions, never()).findByFeedIdAndStatus(anyLong(), any());
    }

    @Test
    void downloadFailureEmitsOneLineAndTheJobSavesNothing() throws Exception {
        // FeedService.download stores the failed attempt itself before rethrowing
        Feed broken = feed(5, "Broken", null, null);
        when(service.download(5L)).thenThrow(new IllegalStateException("boom"));

        List<String> lines = run(broken);

        assertThat(lines).containsExactly("Broken failed, boom");
        verifyJobSavedNothing();
        assertThat(currentVersions.get(5L).getStatus()).isEqualTo(FeedVersion.CURRENT);
    }

    @Test
    void consumerFailureOnAnUpToDateFeedNeverMarksItFailedOrSaves() throws Exception {
        Feed fresh = feed(3, "Fresh", existingZip().toString(), LocalDate.now().plusDays(30));
        Feed next = feed(4, "Next", existingZip().toString(), LocalDate.now().plusDays(30));
        stubFeeds(fresh, next);

        assertThatThrownBy(() -> job.updateFeeds(line -> { throw new RuntimeException("Broken pipe"); }))
                .hasMessage("Broken pipe");

        // the client is gone: the run stops, nothing is persisted, the version keeps its status
        verifyJobSavedNothing();
        verify(repo, never()).findById(anyLong());
        assertThat(currentVersions.get(3L).getStatus()).isEqualTo(FeedVersion.CURRENT);
        verify(service, never()).download(anyLong());
    }

    @Test
    void consumerFailureAfterASuccessfulDownloadDoesNotSaveFromTheJob() throws Exception {
        Feed noExpiry = feed(1, "NoExpiry", existingZip().toString(), null);
        stubFeeds(noExpiry);

        assertThatThrownBy(() -> job.updateFeeds(line -> { throw new RuntimeException("Broken pipe"); }))
                .hasMessage("Broken pipe");

        verify(service, times(1)).download(1L);
        verifyJobSavedNothing();
        verify(repo, never()).findById(anyLong());
    }

    @Test
    void successfulDownloadIsNotSavedAgainByTheJob() throws Exception {
        // FeedService.download saves the new version itself; the job must not save anything on top of it
        run(feed(1, "NoExpiry", existingZip().toString(), null));

        verify(service, times(1)).download(1L);
        verifyJobSavedNothing();
    }

    @Test
    void mixedListEmitsExactlyOneLinePerFeedInOrder() throws Exception {
        String present = existingZip().toString();
        Feed missingPath = feed(1, "NoPath", null, LocalDate.now().plusYears(1));
        Feed noExpiry = feed(2, "NoExpiry", present, null);
        Feed fresh = feed(3, "Fresh", present, LocalDate.now().plusDays(30));
        Feed expiring = feed(4, "Expiring", present, LocalDate.now().plusDays(2));
        Feed downloadFails = feed(5, "DownloadFails", null, null);
        Feed fresh2 = feed(6, "Fresh2", present, LocalDate.now().plusYears(2));
        when(service.download(5L)).thenThrow(new IllegalStateException("source returned 403"));

        List<String> lines = run(missingPath, noExpiry, fresh, expiring, downloadFails, fresh2);

        assertThat(lines).containsExactly(
                "NoPath has been updated!",
                "NoExpiry has been updated!",
                "Fresh is up to date!",
                "Expiring has been updated!",
                "DownloadFails failed, source returned 403",
                "Fresh2 is up to date!");
        verify(service).download(1L);
        verify(service).download(2L);
        verify(service, never()).download(3L);
        verify(service).download(4L);
        verify(service).download(5L);
        verify(service, never()).download(6L);
        verifyZipNeverRead();
        verifyJobSavedNothing();
    }

    @Test
    void sameFileFromTheSourceIsReportedAsUnchangedNotAsUpdated() throws Exception {
        Feed expiring = feed(1, "Same", existingZip().toString(), LocalDate.now().plusDays(2));
        Feed fresh = feed(2, "Fresh", existingZip().toString(), LocalDate.now().plusDays(30));
        Feed changed = feed(3, "Changed", null, null);
        when(service.download(1L)).thenReturn(new DownloadResult(currentVersions.get(1L), true));

        List<String> lines = run(expiring, fresh, changed);

        // "is up to date!" = no download needed; "is unchanged" = we downloaded, but the source has nothing newer
        assertThat(lines).containsExactly("Same is unchanged", "Fresh is up to date!", "Changed has been updated!");
        verifyJobSavedNothing();
    }

    @Test
    void scheduledVariantRunsSameLogicWithoutConsumer() throws Exception {
        stubFeeds(feed(1, "NoPath", null, null));

        job.updateFeedsScheduled();

        verify(service, times(1)).download(1L);
    }

    @Test
    void noFeedsMeansNoLines() {
        assertThat(run()).isEmpty();
        verifyNoInteractions(service);
    }

    // ---- interruption (r19) ----

    /** Three feeds that all need a download: missing file, expiring in 2 days, null expiresOn. */
    private Feed[] threeFeedsThatAllNeedADownload() throws IOException {
        return new Feed[] {
                feed(1, "Cluj", null, LocalDate.now().plusYears(1)),
                feed(2, "Iasi", existingZip().toString(), LocalDate.now().plusDays(2)),
                feed(3, "Brasov", existingZip().toString(), null)
        };
    }

    @SuppressWarnings("unchecked")
    private static Consumer<String> consumer() {
        return mock(Consumer.class);
    }

    /** Runs updateFeeds and returns the interrupt flag as it was right after the call, clearing it immediately. */
    private boolean runAndTakeInterruptFlag(Consumer<String> onResult) {
        boolean flag;
        try {
            job.updateFeeds(onResult);
        } finally {
            flag = Thread.interrupted(); // cleared even if updateFeeds throws; the exception still propagates
        }
        return flag;
    }

    @Test
    void interruptOnTheSecondFeedStopsTheRunReportsItOnceAndRestoresTheFlag() throws Exception {
        Feed[] f = threeFeedsThatAllNeedADownload();
        stubFeeds(f);
        when(service.download(1L)).thenReturn(new DownloadResult(currentVersions.get(1L), false));
        when(service.download(2L)).thenThrow(new InterruptedException("shutdown"));
        Consumer<String> onResult = consumer();
        assertThat(Thread.currentThread().isInterrupted()).isFalse();

        boolean flagAfter = runAndTakeInterruptFlag(onResult);

        assertThat(flagAfter).as("interrupt flag restored for the caller").isTrue();
        ArgumentCaptor<String> lines = ArgumentCaptor.forClass(String.class);
        verify(onResult, times(2)).accept(lines.capture());
        assertThat(lines.getAllValues()).containsExactly("Cluj has been updated!", "Iasi interrupted, update stopped");
        InOrder order = inOrder(versions, repo, service, onResult);
        order.verify(versions).findCurrentByFeedId();
        order.verify(repo).findAll();
        order.verify(service).download(1L);
        order.verify(onResult).accept("Cluj has been updated!");
        order.verify(service).download(2L);
        order.verify(onResult).accept("Iasi interrupted, update stopped");
        verify(service, never()).download(3L);
        // the job itself marks nothing failed: FeedService.download already stored #2's failure before rethrowing
        verifyNoMoreInteractions(repo, versions, service, onResult);
        assertThat(currentVersions.get(2L).getStatus()).isEqualTo(FeedVersion.CURRENT);
        assertThat(currentVersions.get(3L).getStatus()).isEqualTo(FeedVersion.CURRENT);
    }

    @Test
    void interruptOnTheFirstFeedEmitsOneLineAndDownloadsNothingAfterIt() throws Exception {
        Feed[] f = threeFeedsThatAllNeedADownload();
        stubFeeds(f);
        when(service.download(1L)).thenThrow(new InterruptedException("shutdown"));
        Consumer<String> onResult = consumer();

        boolean flagAfter = runAndTakeInterruptFlag(onResult);

        assertThat(flagAfter).isTrue();
        verify(onResult).accept("Cluj interrupted, update stopped");
        verify(service).download(1L);
        verify(service, never()).download(2L);
        verify(service, never()).download(3L);
        verify(repo).findAll();
        verify(versions).findCurrentByFeedId();
        verifyNoMoreInteractions(repo, versions, service, onResult);
    }

    @Test
    void plainExceptionOnTheSecondFeedStillContinuesToTheThirdAndLeavesNoInterruptFlag() throws Exception {
        Feed[] f = threeFeedsThatAllNeedADownload();
        stubFeeds(f);
        when(service.download(2L)).thenThrow(new IOException("connection reset"));
        Consumer<String> onResult = consumer();

        boolean flagAfter = runAndTakeInterruptFlag(onResult);

        assertThat(flagAfter).as("a plain failure must not set the interrupt flag").isFalse();
        ArgumentCaptor<String> lines = ArgumentCaptor.forClass(String.class);
        verify(onResult, times(3)).accept(lines.capture());
        assertThat(lines.getAllValues()).containsExactly(
                "Cluj has been updated!", "Iasi failed, connection reset", "Brasov has been updated!");
        InOrder order = inOrder(service);
        order.verify(service).download(1L);
        order.verify(service).download(2L);
        order.verify(service).download(3L);
        verifyJobSavedNothing();
        assertThat(currentVersions.get(2L).getStatus()).isEqualTo(FeedVersion.CURRENT);
    }

    @Test
    void scheduledRunStopsOnInterruptReturnsNormallyAndLeavesTheFlagSet() throws Exception {
        Feed[] f = threeFeedsThatAllNeedADownload();
        stubFeeds(f);
        when(service.download(2L)).thenThrow(new InterruptedException("shutdown"));

        boolean flagAfter;
        try {
            job.updateFeedsScheduled(); // must not throw: the scheduler would only log it
        } finally {
            flagAfter = Thread.interrupted();
        }

        assertThat(flagAfter).isTrue();
        verify(service).download(1L);
        verify(service).download(2L);
        verify(service, never()).download(3L);
        verifyJobSavedNothing();
    }
}
