package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** FeedUpdateJob with mocked repository/service: exactly one result line per feed, downloads only when needed. */
class FeedUpdateJobTest {

    private final FeedRepository repo = mock(FeedRepository.class);
    private final FeedService service = mock(FeedService.class);
    private final FeedUpdateJob job = new FeedUpdateJob(repo, service);

    @TempDir
    Path tmp;

    private Feed feed(long id, String city, String localPath) {
        Feed feed = new Feed();
        ReflectionTestUtils.setField(feed, "id", id);
        feed.setCityName(city);
        feed.setCompanyName(city + "Co");
        feed.setSourceId("mdb-" + id);
        feed.setLocalPath(localPath);
        return feed;
    }

    @Test
    void emitsExactlyOneLinePerFeedAndDownloadsOnlyMissingOrExpiringFeeds() throws Exception {
        Path present = Files.createFile(tmp.resolve("present.zip"));
        Feed missingPath = feed(1, "NoPath", null);
        Feed missingFile = feed(2, "NoFile", tmp.resolve("gone.zip").toString());
        Feed fresh = feed(3, "Fresh", present.toString());
        Feed expiring = feed(4, "Expiring", present.toString());
        Feed broken = feed(5, "Broken", present.toString());
        Feed downloadFails = feed(6, "DownloadFails", null);
        when(repo.findAll()).thenReturn(List.of(missingPath, missingFile, fresh, expiring, broken, downloadFails));
        when(service.getExpireDate(3L)).thenReturn(LocalDate.now().plusDays(30));
        when(service.getExpireDate(4L)).thenReturn(LocalDate.now().plusDays(2));
        when(service.getExpireDate(5L)).thenThrow(new IllegalStateException("feed_info.txt is missing"));
        when(service.download(6L)).thenThrow(new IllegalStateException("boom"));

        List<String> lines = new ArrayList<>();
        job.updateFeeds(lines::add);

        assertThat(lines).containsExactly(
                "NoPath has been updated!",
                "NoFile has been updated!",
                "Fresh is up to date!",
                "Expiring has been updated!",
                "Broken failed, feed_info.txt is missing",
                "DownloadFails failed, boom");
        verify(service, times(1)).download(1L);
        verify(service, times(1)).download(2L);
        verify(service, never()).download(3L);
        verify(service, times(1)).download(4L);
        verify(service, never()).download(5L);
        verify(service, never()).getExpireDate(1L);
        verify(service, never()).getExpireDate(2L);
    }

    @Test
    void scheduledVariantRunsSameLogicWithoutConsumer() throws Exception {
        Feed missingPath = feed(1, "NoPath", null);
        when(repo.findAll()).thenReturn(List.of(missingPath));

        job.updateFeedsScheduled();

        verify(service, times(1)).download(1L);
    }

    @Test
    void noFeedsMeansNoLines() {
        when(repo.findAll()).thenReturn(List.of());
        List<String> lines = new ArrayList<>();
        job.updateFeeds(lines::add);
        assertThat(lines).isEmpty();
        verifyNoInteractions(service);
    }
}
