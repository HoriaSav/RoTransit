package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * FeedService.getExpireDate on small zips built in a @TempDir (no DB, no network).
 * The repository is mocked to return a Feed whose localPath points at the temp zip.
 */
class FeedServiceExpireDateTest {

    private static final String CAL = "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n";
    private static final String CAL_DATES = "service_id,date,exception_type\n";

    private final FeedRepository repo = mock(FeedRepository.class);
    private final FeedService service = new FeedService(repo);

    @TempDir
    Path tmp;

    private LocalDate expiry(Map<String, String> files) throws IOException {
        Path zip = tmp.resolve("feed.zip");
        try (ZipOutputStream out = new ZipOutputStream(Files.newOutputStream(zip))) {
            for (Map.Entry<String, String> e : files.entrySet()) {
                out.putNextEntry(new ZipEntry(e.getKey()));
                out.write(e.getValue().getBytes(StandardCharsets.UTF_8));
                out.closeEntry();
            }
        }
        return expiryOf(zip.toString());
    }

    private LocalDate expiryOf(String localPath) throws IOException {
        Feed feed = new Feed();
        ReflectionTestUtils.setField(feed, "id", 1L);
        feed.setLocalPath(localPath);
        when(repo.findById(1L)).thenReturn(Optional.of(feed));
        return service.getExpireDate(1L);
    }

    private static Map<String, String> files(String... nameContentPairs) {
        Map<String, String> m = new LinkedHashMap<>();
        for (int i = 0; i < nameContentPairs.length; i += 2) {
            m.put(nameContentPairs[i], nameContentPairs[i + 1]);
        }
        return m;
    }

    // ---- fallback order ----

    @Test
    void feedInfoEndDateWinsEvenIfCalendarIsLater() throws Exception {
        assertThat(expiry(files(
                "feed_info.txt", "feed_publisher_name,feed_publisher_url,feed_lang,feed_end_date\nP,https://x,ro,20270101\n",
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,20291231\n",
                "calendar_dates.txt", CAL_DATES + "wk,20301231,1\n")))
                .isEqualTo(LocalDate.of(2027, 1, 1));
    }

    @Test
    void feedInfoAloneIsEnough() throws Exception {
        assertThat(expiry(files(
                "feed_info.txt", "feed_publisher_name,feed_publisher_url,feed_lang,feed_end_date\nP,https://x,ro,20301231\n")))
                .isEqualTo(LocalDate.of(2030, 12, 31));
    }

    @Test
    void calendarIsUsedWhenThereIsNoFeedInfo() throws Exception {
        assertThat(expiry(files(
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,20271231\n",
                "calendar_dates.txt", CAL_DATES + "wk,20291231,1\n")))
                .isEqualTo(LocalDate.of(2027, 12, 31));
    }

    @Test
    void calendarDatesIsUsedWhenFeedInfoAndCalendarAreMissing() throws Exception {
        assertThat(expiry(files("calendar_dates.txt", CAL_DATES + "wk,20270315,1\n")))
                .isEqualTo(LocalDate.of(2027, 3, 15));
    }

    @Test
    void feedInfoWithoutEndDateColumnFallsThroughToCalendar() throws Exception {
        assertThat(expiry(files(
                "feed_info.txt", "feed_publisher_name,feed_publisher_url,feed_lang,feed_version\nP,https://x,ro,1.0\n",
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,20270630\n")))
                .isEqualTo(LocalDate.of(2027, 6, 30));
    }

    @Test
    void feedInfoWithEmptyEndDateFallsThroughToCalendar() throws Exception {
        assertThat(expiry(files(
                "feed_info.txt", "feed_publisher_name,feed_publisher_url,feed_lang,feed_end_date\nP,https://x,ro,\n",
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,20270630\n")))
                .isEqualTo(LocalDate.of(2027, 6, 30));
    }

    @Test
    void calendarWithOnlyEmptyEndDatesFallsThroughToCalendarDates() throws Exception {
        assertThat(expiry(files(
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,\nwe,0,0,0,0,0,1,1,20260101,  \n",
                "calendar_dates.txt", CAL_DATES + "wk,20270101,1\n")))
                .isEqualTo(LocalDate.of(2027, 1, 1));
    }

    @Test
    void headerOnlyFilesFallThrough() throws Exception {
        assertThat(expiry(files(
                "feed_info.txt", "",
                "calendar.txt", CAL,
                "calendar_dates.txt", CAL_DATES + "wk,20270202,1\n")))
                .isEqualTo(LocalDate.of(2027, 2, 2));
    }

    // ---- latest = max over all rows ----

    @Test
    void latestEndDateAcrossSeveralCalendarRows() throws Exception {
        assertThat(expiry(files("calendar.txt", CAL
                + "a,1,1,1,1,1,0,0,20260101,20261231\n"
                + "b,1,1,1,1,1,0,0,20260101,20280115\n"
                + "c,1,1,1,1,1,0,0,20260101,20270601\n")))
                .isEqualTo(LocalDate.of(2028, 1, 15));
    }

    @Test
    void latestDateAcrossUnsortedCalendarDates() throws Exception {
        assertThat(expiry(files("calendar_dates.txt", CAL_DATES
                + "wk,20261224,2\nwk,20280229,1\nwk,20270101,1\nwk,20261001,1\n")))
                .isEqualTo(LocalDate.of(2028, 2, 29));
    }

    @Test
    void emptyValuesAndShortRowsAreSkipped() throws Exception {
        assertThat(expiry(files("calendar.txt", CAL
                + "a,1,1,1,1,1,0,0,20260101,\n"
                + "short,1,1\n"
                + "\n"
                + "b,1,1,1,1,1,0,0,20260101,20270808\n")))
                .isEqualTo(LocalDate.of(2027, 8, 8));
    }

    // ---- CSV shapes ----

    @Test
    void columnsAreLookedUpByNameInAnyOrder() throws Exception {
        assertThat(expiry(files(
                "calendar.txt", "end_date,service_id,start_date,monday,tuesday,wednesday,thursday,friday,saturday,sunday\n"
                        + "20271111,wk,20260101,1,1,1,1,1,0,0\n")))
                .isEqualTo(LocalDate.of(2027, 11, 11));
        assertThat(expiry(files("calendar_dates.txt", "exception_type,service_id,date\n1,wk,20270909\n")))
                .isEqualTo(LocalDate.of(2027, 9, 9));
    }

    @Test
    void crlfLineEndingsAndWhitespaceAroundValuesAreHandled() throws Exception {
        assertThat(expiry(files("calendar.txt", (CAL.replace("\n", "\r\n"))
                + "a,1,1,1,1,1,0,0,20260101, 20270707 \r\n"
                + "b,1,1,1,1,1,0,0,20260101,20270101\r\n")))
                .isEqualTo(LocalDate.of(2027, 7, 7));
    }

    @Test
    void quotedHeaderNamesAndQuotedValuesWithoutCommasAreHandled() throws Exception {
        assertThat(expiry(files("calendar_dates.txt",
                "\"service_id\",\"date\",\"exception_type\"\n\"wk\",\"20270404\",\"1\"\n")))
                .isEqualTo(LocalDate.of(2027, 4, 4));
    }

    @Test
    void utf8BomBeforeTheLookedUpFirstColumnIsIgnored() throws Exception {
        assertThat(expiry(files("calendar_dates.txt", "\uFEFFdate,service_id,exception_type\n20301231,wk,1\n")))
                .isEqualTo(LocalDate.of(2030, 12, 31));
    }

    @Test
    void utf8BomOnFeedInfoIsIgnored() throws Exception {
        // feed_end_date first, so without BOM stripping the column is not found and calendar (2029) would win
        assertThat(expiry(files(
                "feed_info.txt", "\uFEFFfeed_end_date,feed_publisher_name,feed_publisher_url,feed_lang\n20280531,P,https://x,ro\n",
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,20291231\n")))
                .isEqualTo(LocalDate.of(2028, 5, 31));
    }

    // ---- failure behavior ----

    @Test
    void noUsableSourceThrowsIllegalState() {
        assertThatThrownBy(() -> expiry(files("stops.txt", "stop_id,stop_name\n1,A\n")))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("no expiry date found");
    }

    @Test
    void missingZipThrowsNoSuchFile() {
        assertThatThrownBy(() -> expiryOf(tmp.resolve("does-not-exist.zip").toString()))
                .isInstanceOf(NoSuchFileException.class);
    }

    @Test
    void unparseableDateRowsAreSkippedAndGoodRowsStillCount() throws Exception {
        assertThat(expiry(files("calendar.txt", CAL
                + "a,1,1,1,1,1,0,0,20260101,2027-12-09\n"
                + "b,1,1,1,1,1,0,0,20260101,20270505\n"
                + "c,1,1,1,1,1,0,0,20260101,abc\n")))
                .isEqualTo(LocalDate.of(2027, 5, 5));
        assertThat(expiry(files("calendar_dates.txt", CAL_DATES + "wk,abc,1\nwk,20270303,1\nwk,2027-12-09,1\n")))
                .isEqualTo(LocalDate.of(2027, 3, 3));
    }

    @Test
    void sourceWithOnlyUnparseableDatesFallsThroughToTheNextSource() throws Exception {
        // bad feed_info -> calendar
        assertThat(expiry(files(
                "feed_info.txt", "feed_publisher_name,feed_publisher_url,feed_lang,feed_end_date\nP,https://x,ro,2027-12-09\n",
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,20270606\n")))
                .isEqualTo(LocalDate.of(2027, 6, 6));
        // bad feed_info and bad calendar -> calendar_dates
        assertThat(expiry(files(
                "feed_info.txt", "feed_publisher_name,feed_publisher_url,feed_lang,feed_end_date\nP,https://x,ro,abc\n",
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,2027-12-09\nwe,0,0,0,0,0,1,1,20260101,abc\n",
                "calendar_dates.txt", CAL_DATES + "wk,20270707,1\n")))
                .isEqualTo(LocalDate.of(2027, 7, 7));
    }

    @Test
    void allSourcesWithOnlyUnparseableDatesThrowNoExpiryDate() {
        assertThatThrownBy(() -> expiry(files(
                "feed_info.txt", "feed_publisher_name,feed_publisher_url,feed_lang,feed_end_date\nP,https://x,ro,2027-12-09\n",
                "calendar.txt", CAL + "wk,1,1,1,1,1,0,0,20260101,abc\n",
                "calendar_dates.txt", CAL_DATES + "wk,abc,1\nwk,2027-12-09,1\n")))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("no expiry date found");
    }
}
