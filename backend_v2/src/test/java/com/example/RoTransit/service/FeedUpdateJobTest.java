package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.same;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

/**
 * FeedUpdateJob with mocked repository/service. The job decides from the stored expiresOn (and whether the
 * local file exists); it must never open the zip itself (no getExpireDate/readExpireDate calls).
 * The job uses LocalDate.now() directly, so dates here are relative to LocalDate.now().
 */
class FeedUpdateJobTest {

    private final FeedRepository repo = mock(FeedRepository.class);
    private final FeedService service = mock(FeedService.class);
    private final FeedUpdateJob job = new FeedUpdateJob(repo, service);

    @TempDir
    Path tmp;

    /** Guard: an interrupt test must never leak the flag into the next test, even when it fails half-way. */
    @AfterEach
    void clearInterruptFlag() {
        Thread.interrupted();
    }

    private Path existingZip() throws IOException {
        return Files.createFile(tmp.resolve("present-" + System.nanoTime() + ".zip"));
    }

    private Feed feed(long id, String city, String localPath, LocalDate expiresOn) {
        Feed feed = new Feed();
        ReflectionTestUtils.setField(feed, "id", id);
        feed.setCityName(city);
        feed.setCompanyName(city + "Co");
        feed.setSourceId("mdb-" + id);
        feed.setStatus("downloaded");
        feed.setLocalPath(localPath);
        feed.setExpiresOn(expiresOn);
        return feed;
    }

    private List<String> run(Feed... feeds) {
        when(repo.findAll()).thenReturn(List.of(feeds));
        List<String> lines = new ArrayList<>();
        job.updateFeeds(lines::add);
        return lines;
    }

    private void verifyZipNeverRead() throws IOException {
        verify(service, never()).getExpireDate(any());
        verify(service, never()).readExpireDate(any());
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   ", "/definitely/not/here/feed.zip"})
    void missingLocalFileDownloadsEvenWhenExpiryIsFarAway(String localPath) throws Exception {
        List<String> lines = run(feed(1, "NoFile", localPath, LocalDate.now().plusYears(1)));

        assertThat(lines).containsExactly("NoFile has been updated!");
        verify(service, times(1)).download(1L);
        verifyZipNeverRead();
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
        verify(repo, never()).save(any());
    }

    @Test
    void downloadFailureSavesStatusFailedOnAFreshCopyOfTheRowAndEmitsOneLine() throws Exception {
        Feed stale = feed(5, "Broken", null, null);
        Feed fresh = feed(5, "Broken", null, null);
        fresh.setExpiresOn(LocalDate.of(2027, 1, 1)); // something only the DB copy knows
        when(service.download(5L)).thenThrow(new IllegalStateException("boom"));
        when(repo.findById(5L)).thenReturn(Optional.of(fresh));

        List<String> lines = run(stale);

        assertThat(lines).containsExactly("Broken failed, boom");
        verify(repo, times(1)).save(same(fresh));
        verify(repo, never()).save(same(stale));
        assertThat(fresh.getStatus()).isEqualTo("failed");
        assertThat(fresh.getExpiresOn()).isEqualTo(LocalDate.of(2027, 1, 1));
        assertThat(stale.getStatus()).isEqualTo("downloaded");
    }

    @Test
    void downloadFailureForARowDeletedMeanwhileStillEmitsOneLineAndSavesNothing() throws Exception {
        when(service.download(5L)).thenThrow(new IllegalStateException("boom"));
        when(repo.findById(5L)).thenReturn(Optional.empty());

        List<String> lines = run(feed(5, "Gone", null, null));

        assertThat(lines).containsExactly("Gone failed, boom");
        verify(repo, never()).save(any());
    }

    @Test
    void consumerFailureOnAnUpToDateFeedNeverMarksItFailedOrSaves() throws Exception {
        Feed fresh = feed(3, "Fresh", existingZip().toString(), LocalDate.now().plusDays(30));
        Feed next = feed(4, "Next", existingZip().toString(), LocalDate.now().plusDays(30));
        when(repo.findAll()).thenReturn(List.of(fresh, next));

        assertThatThrownBy(() -> job.updateFeeds(line -> { throw new RuntimeException("Broken pipe"); }))
                .hasMessage("Broken pipe");

        // the client is gone: the run stops, nothing is persisted, the feed keeps its status
        verify(repo, never()).save(any());
        verify(repo, never()).findById(anyLong());
        assertThat(fresh.getStatus()).isEqualTo("downloaded");
        verify(service, never()).download(anyLong());
    }

    @Test
    void consumerFailureAfterASuccessfulDownloadDoesNotSaveFromTheJob() throws Exception {
        Feed noExpiry = feed(1, "NoExpiry", existingZip().toString(), null);
        when(repo.findAll()).thenReturn(List.of(noExpiry));

        assertThatThrownBy(() -> job.updateFeeds(line -> { throw new RuntimeException("Broken pipe"); }))
                .hasMessage("Broken pipe");

        verify(service, times(1)).download(1L);
        verify(repo, never()).save(any());
        verify(repo, never()).findById(anyLong());
        assertThat(noExpiry.getStatus()).isEqualTo("downloaded");
    }

    @Test
    void successfulDownloadIsNotSavedAgainByTheJob() throws Exception {
        // FeedService.download saves the updated feed itself; the job must not overwrite it with its stale copy
        run(feed(1, "NoExpiry", existingZip().toString(), null));

        verify(service, times(1)).download(1L);
        verify(repo, never()).save(any());
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
        Feed downloadFailsFromDb = feed(5, "DownloadFails", null, null);
        when(service.download(5L)).thenThrow(new IllegalStateException("source returned 403"));
        when(repo.findById(5L)).thenReturn(Optional.of(downloadFailsFromDb));

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
        verify(repo, times(1)).save(same(downloadFailsFromDb));
        assertThat(downloadFailsFromDb.getStatus()).isEqualTo("failed");
        assertThat(fresh.getStatus()).isEqualTo("downloaded");
    }

    @Test
    void scheduledVariantRunsSameLogicWithoutConsumer() throws Exception {
        when(repo.findAll()).thenReturn(List.of(feed(1, "NoPath", null, null)));

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
        when(repo.findAll()).thenReturn(List.of(f));
        when(service.download(1L)).thenReturn(f[0]);
        when(service.download(2L)).thenThrow(new InterruptedException("shutdown"));
        Consumer<String> onResult = consumer();
        assertThat(Thread.currentThread().isInterrupted()).isFalse();

        boolean flagAfter = runAndTakeInterruptFlag(onResult);

        assertThat(flagAfter).as("interrupt flag restored for the caller").isTrue();
        ArgumentCaptor<String> lines = ArgumentCaptor.forClass(String.class);
        verify(onResult, times(2)).accept(lines.capture());
        assertThat(lines.getAllValues()).containsExactly("Cluj has been updated!", "Iasi interrupted, update stopped");
        InOrder order = inOrder(repo, service, onResult);
        order.verify(repo).findAll();
        order.verify(service).download(1L);
        order.verify(onResult).accept("Cluj has been updated!");
        order.verify(service).download(2L);
        order.verify(onResult).accept("Iasi interrupted, update stopped");
        verify(service, never()).download(3L);
        // the job itself marks nothing failed: FeedService.download already saved #2 as failed before rethrowing
        verify(repo, never()).findById(anyLong());
        verify(repo, never()).save(any());
        verifyNoMoreInteractions(repo, service, onResult);
        assertThat(f[1].getStatus()).isEqualTo("downloaded");
        assertThat(f[2].getStatus()).isEqualTo("downloaded");
    }

    @Test
    void interruptOnTheFirstFeedEmitsOneLineAndDownloadsNothingAfterIt() throws Exception {
        Feed[] f = threeFeedsThatAllNeedADownload();
        when(repo.findAll()).thenReturn(List.of(f));
        when(service.download(1L)).thenThrow(new InterruptedException("shutdown"));
        Consumer<String> onResult = consumer();

        boolean flagAfter = runAndTakeInterruptFlag(onResult);

        assertThat(flagAfter).isTrue();
        verify(onResult).accept("Cluj interrupted, update stopped");
        verify(service).download(1L);
        verify(service, never()).download(2L);
        verify(service, never()).download(3L);
        verify(repo).findAll();
        verifyNoMoreInteractions(repo, service, onResult);
    }

    @Test
    void plainExceptionOnTheSecondFeedStillContinuesToTheThirdAndLeavesNoInterruptFlag() throws Exception {
        Feed[] f = threeFeedsThatAllNeedADownload();
        Feed iasiFromDb = feed(2, "Iasi", f[1].getLocalPath(), f[1].getExpiresOn());
        when(repo.findAll()).thenReturn(List.of(f));
        when(service.download(2L)).thenThrow(new IOException("connection reset"));
        when(repo.findById(2L)).thenReturn(Optional.of(iasiFromDb));
        Consumer<String> onResult = consumer();

        boolean flagAfter = runAndTakeInterruptFlag(onResult);

        assertThat(flagAfter).as("a plain failure must not set the interrupt flag").isFalse();
        ArgumentCaptor<String> lines = ArgumentCaptor.forClass(String.class);
        verify(onResult, times(3)).accept(lines.capture());
        assertThat(lines.getAllValues()).containsExactly(
                "Cluj has been updated!", "Iasi failed, connection reset", "Brasov has been updated!");
        InOrder order = inOrder(service, repo);
        order.verify(service).download(1L);
        order.verify(service).download(2L);
        order.verify(repo).findById(2L);
        order.verify(repo).save(same(iasiFromDb));
        order.verify(service).download(3L);
        assertThat(iasiFromDb.getStatus()).isEqualTo("failed");
        assertThat(f[1].getStatus()).isEqualTo("downloaded");
    }

    @Test
    void scheduledRunStopsOnInterruptReturnsNormallyAndLeavesTheFlagSet() throws Exception {
        Feed[] f = threeFeedsThatAllNeedADownload();
        when(repo.findAll()).thenReturn(List.of(f));
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
        verify(repo, never()).save(any());
    }
}
