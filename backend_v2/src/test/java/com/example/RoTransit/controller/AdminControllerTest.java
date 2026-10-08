package com.example.RoTransit.controller;

import com.example.RoTransit.TestEntities;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedSourceRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import com.example.RoTransit.service.DownloadResult;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Optional;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.aMapWithSize;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Standalone MockMvc tests for AdminController (/admin/feeds...). No Spring context, no DB, no network.
 * The tests moved here from FeedControllerTest keep their original assertions; only the paths changed.
 */
class AdminControllerTest {

    private final FeedRepository repo = mock(FeedRepository.class);
    private final FeedSourceRepository sources = mock(FeedSourceRepository.class);
    private final FeedVersionRepository versions = mock(FeedVersionRepository.class);
    private final FeedService feedService = mock(FeedService.class);
    private final FeedUpdateJob feedUpdateJob = mock(FeedUpdateJob.class);
    private MockMvc mvc;

    /** What the mocked repositories return for the list: feeds, their current versions and their latest attempts. */
    private final List<Feed> feedList = new ArrayList<>();
    private final Map<Long, FeedVersion> currentVersions = new HashMap<>();
    private final Map<Long, FeedVersion> latestVersions = new HashMap<>();

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new AdminController(repo, sources, versions, feedService, feedUpdateJob)).build();
        when(repo.findAll()).thenReturn(feedList);
        when(versions.findCurrentByFeedId()).thenReturn(currentVersions);
        when(versions.findLatestByFeedId()).thenReturn(latestVersions);
    }

    /** A downloaded feed (current version = latest attempt) that shows up in the list, also stubbed for /admin/feeds/{id}. */
    private Feed feed(long id, String city, LocalDate expiresOn) {
        Feed feed = TestEntities.feed(id, city, city + "Co");
        FeedVersion current = TestEntities.current(feed, "feeds/" + id + ".zip", expiresOn);
        current.setDownloadedAt(Instant.parse("2026-10-0" + (id % 9 + 1) + "T08:00:00Z"));
        current.setSource(TestEntities.mobilityDbSource(feed, "mdb-" + id));
        feedList.add(feed);
        currentVersions.put(id, current);
        latestVersions.put(id, current);
        when(repo.findById(id)).thenReturn(Optional.of(feed));
        when(sources.findByFeedIdAndPriority(id, 1)).thenReturn(Optional.of(current.getSource()));
        when(versions.findByFeedIdAndStatus(id, FeedVersion.CURRENT)).thenReturn(Optional.of(current));
        when(versions.findFirstByFeedIdOrderByIdDesc(id)).thenReturn(Optional.of(current));
        return feed;
    }

    // ---- moved from FeedControllerTest (paths now under /admin) ----

    @Test
    @SuppressWarnings("unchecked")
    void updateStreamsPlainTextLines() throws Exception {
        doAnswer(inv -> {
            Consumer<String> onResult = inv.getArgument(0);
            onResult.accept("Brasov is up to date!");
            onResult.accept("Cluj-Napoca has been updated!");
            return null;
        }).when(feedUpdateJob).updateFeeds(any(Consumer.class));

        MvcResult result = mvc.perform(post("/admin/feeds/update"))
                .andExpect(request().asyncStarted())
                .andReturn();

        mvc.perform(asyncDispatch(result))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_PLAIN))
                .andExpect(content().string("Brasov is up to date!\nCluj-Napoca has been updated!\n"));
    }

    @Test
    void createFeedPassesOnlyCityCompanyAndSourceAndIgnoresSpoofedFields() throws Exception {
        Feed created = TestEntities.feed(42L, "Probe", "ProbeCo");
        when(feedService.createFeed("Probe", "ProbeCo", "mdb-probe")).thenReturn(created);
        when(sources.findByFeedIdAndPriority(42L, 1))
                .thenReturn(Optional.of(TestEntities.mobilityDbSource(created, "mdb-probe")));

        mvc.perform(post("/admin/feeds")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"cityName":"Probe","companyName":"ProbeCo","sourceId":"mdb-probe",
                                 "localPath":"/etc/passwd","filePath":"/etc/passwd","status":"hacked","id":5}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(42))
                .andExpect(jsonPath("$.cityName").value("Probe"))
                .andExpect(jsonPath("$.companyName").value("ProbeCo"))
                .andExpect(jsonPath("$.sourceId").value("mdb-probe"))
                .andExpect(jsonPath("$.sourceUrl").value(nullValue()))
                .andExpect(jsonPath("$.status").value("new")) // no versions yet, not the "hacked" value from the body
                .andExpect(jsonPath("$.downloadedAt").value(nullValue()))
                .andExpect(jsonPath("$.localPath").doesNotExist())
                .andExpect(jsonPath("$.filePath").doesNotExist());

        // only these three values reach the service; the spoofed fields have nowhere to go
        verify(feedService).createFeed("Probe", "ProbeCo", "mdb-probe");
    }

    @Test
    void feedJsonNeverExposesLocalPath() throws Exception {
        feed(3L, "Testville", LocalDate.of(2027, 1, 1));

        mvc.perform(get("/admin/feeds/3"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(3))
                .andExpect(jsonPath("$.localPath").doesNotExist())
                .andExpect(jsonPath("$.filePath").doesNotExist());
        // GET /feeds is gone; the admin list (FeedStatus) is the replacement
        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].localPath").doesNotExist())
                .andExpect(jsonPath("$[0].filePath").doesNotExist());
    }

    @Test
    void feedDetailsHaveTheOldFeedFieldsFromTheCurrentVersion() throws Exception {
        feed(3L, "Testville", LocalDate.of(2027, 1, 1));
        currentVersions.get(3L).setStartsOn(LocalDate.of(2026, 9, 1));

        mvc.perform(get("/admin/feeds/3"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", aMapWithSize(9)))
                .andExpect(jsonPath("$.cityName").value("Testville"))
                .andExpect(jsonPath("$.companyName").value("TestvilleCo"))
                .andExpect(jsonPath("$.sourceId").value("mdb-3"))
                .andExpect(jsonPath("$.sourceUrl").value("https://files.mobilitydatabase.org/mdb-3/latest.zip"))
                .andExpect(jsonPath("$.status").value("downloaded"))
                .andExpect(jsonPath("$.downloadedAt").value("2026-10-04T08:00:00Z"))
                .andExpect(jsonPath("$.startsOn").value("2026-09-01"))
                .andExpect(jsonPath("$.expiresOn").value("2027-01-01"));
    }

    @Test
    void unknownFeedIdIsNotFound() {
        when(repo.findById(99L)).thenReturn(Optional.empty());

        // standalone MockMvc has no GlobalExceptionHandler, so the NoSuchElementException surfaces as is
        assertThatThrownBy(() -> mvc.perform(get("/admin/feeds/99")))
                .hasRootCauseInstanceOf(NoSuchElementException.class);
    }

    // ---- download / expires ----

    @Test
    void downloadReturnsTheFeedWithItsNewCurrentVersionWithoutLocalPath() throws Exception {
        Feed feed = feed(4L, "Testville", LocalDate.of(2027, 12, 31));
        when(feedService.download(4L)).thenReturn(new DownloadResult(currentVersions.get(4L), false));

        mvc.perform(post("/admin/feeds/4/download"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(4))
                .andExpect(jsonPath("$.status").value("downloaded"))
                .andExpect(jsonPath("$.unchanged").value(false))
                .andExpect(jsonPath("$.expiresOn").value("2027-12-31"))
                .andExpect(jsonPath("$.localPath").doesNotExist())
                .andExpect(jsonPath("$.filePath").doesNotExist());
        verify(feedService).download(feed.getId());
    }

    @Test
    void downloadOfTheSameFileSaysUnchanged() throws Exception {
        feed(4L, "Testville", LocalDate.of(2027, 12, 31));
        when(feedService.download(4L)).thenReturn(new DownloadResult(currentVersions.get(4L), true));

        mvc.perform(post("/admin/feeds/4/download"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.unchanged").value(true))
                .andExpect(jsonPath("$.status").value("downloaded"))
                .andExpect(jsonPath("$.expiresOn").value("2027-12-31"));
        // only the download response has the field
        mvc.perform(get("/admin/feeds/4"))
                .andExpect(jsonPath("$.unchanged").doesNotExist());
    }

    @Test
    void downloadBadGatewayFromTheSourceStays502() throws Exception {
        when(feedService.download(5L)).thenThrow(new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "source returned 403 for https://files.mobilitydatabase.org/mdb-x/latest.zip"));

        mvc.perform(post("/admin/feeds/5/download"))
                .andExpect(status().isBadGateway());
        // the controller writes nothing itself; FeedService stores the failed attempt
        verify(repo, never()).save(any());
        verify(versions, never()).save(any());
    }

    @Test
    void expiresReturnsTheDateFromTheService() throws Exception {
        when(feedService.getExpireDate(6L)).thenReturn(LocalDate.of(2028, 5, 31));

        mvc.perform(get("/admin/feeds/6/expires"))
                .andExpect(status().isOk())
                .andExpect(content().json("\"2028-05-31\""));
        verify(feedService).getExpireDate(6L);
        verifyNoInteractions(feedUpdateJob);
    }

    // ---- GET /admin/feeds (FeedStatus) ----

    @Test
    void statusListHasExactlyTheFeedStatusFieldsWithCorrectValues() throws Exception {
        LocalDate today = LocalDate.now();
        feed(7L, "Sibiu", today.plusDays(30));

        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0]", aMapWithSize(7)))
                .andExpect(jsonPath("$[0].id").value(7))
                .andExpect(jsonPath("$[0].cityName").value("Sibiu"))
                .andExpect(jsonPath("$[0].companyName").value("SibiuCo"))
                .andExpect(jsonPath("$[0].status").value("downloaded"))
                .andExpect(jsonPath("$[0].downloadedAt").value("2026-10-08T08:00:00Z"))
                .andExpect(jsonPath("$[0].expiresOn").value(today.plusDays(30).toString()))
                .andExpect(jsonPath("$[0].daysLeft").value(30))
                .andExpect(jsonPath("$[0]", not(hasKey("localPath"))))
                .andExpect(jsonPath("$[0]", not(hasKey("sourceId"))))
                .andExpect(jsonPath("$[0]", not(hasKey("sourceUrl"))));
    }

    @Test
    void daysLeftIsDaysFromTodayNegativeWhenExpiredAndNullWithoutExpiry() throws Exception {
        LocalDate today = LocalDate.now();
        feed(1L, "Future", today.plusDays(400));
        feed(2L, "Today", today);
        feed(3L, "Past", today.minusDays(3));
        feed(4L, "Unknown", null);

        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].cityName", contains("Unknown", "Past", "Today", "Future")))
                .andExpect(jsonPath("$[0]", hasKey("daysLeft")))
                .andExpect(jsonPath("$[0].daysLeft").value(nullValue()))
                .andExpect(jsonPath("$[0].expiresOn").value(nullValue()))
                .andExpect(jsonPath("$[1].daysLeft").value(-3))   // expired feeds go negative
                .andExpect(jsonPath("$[2].daysLeft").value(0))
                .andExpect(jsonPath("$[3].daysLeft").value(400));
    }

    @Test
    void statusListIsNullsFirstThenExpiresOnAscendingWithTiesById() throws Exception {
        LocalDate today = LocalDate.now();
        feed(1L, "A", today.plusDays(10));
        feed(2L, "B", null);
        feed(3L, "C", today.minusDays(3));
        feed(4L, "D", today.plusDays(10));
        feed(5L, "E", null);
        feed(6L, "F", today);
        feed(7L, "G", today.plusDays(2));

        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(7)))
                .andExpect(jsonPath("$[*].id", contains(2, 5, 3, 6, 7, 1, 4)))
                .andExpect(jsonPath("$[*].daysLeft", contains(null, null, -3, 0, 2, 10, 10)));
        verifyNoInteractions(feedService, feedUpdateJob);
    }

    @Test
    void tiesAreBrokenByIdWhateverOrderTheRepositoryReturns() throws Exception {
        LocalDate today = LocalDate.now();
        LocalDate same = today.plusDays(20);
        // reverse / shuffled id order on purpose: two nulls, three on the same date, one earlier, one later
        feed(9L, "I", same);
        feed(8L, "H", null);
        feed(7L, "G", today.plusDays(40));
        feed(3L, "C", same);
        feed(6L, "F", null);
        feed(5L, "E", same);
        feed(1L, "A", today.plusDays(1));

        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].id", contains(6, 8, 1, 3, 5, 9, 7)))
                .andExpect(jsonPath("$[*].daysLeft", contains(null, null, 1, 20, 20, 20, 40)));
    }

    @Test
    void emptyRepositoryGivesEmptyStatusList() throws Exception {
        // no feeds added
        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(content().json("[]"));
    }

    @Test
    void statusIsFailedWhenTheLatestAttemptFailedButDatesStayFromTheCurrentVersion() throws Exception {
        LocalDate expires = LocalDate.now().plusDays(30);
        Feed feed = feed(7L, "Sibiu", expires);
        latestVersions.put(7L, TestEntities.version(701L, feed, FeedVersion.FAILED, null, null));

        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].status").value("failed"))
                .andExpect(jsonPath("$[0].downloadedAt").value("2026-10-08T08:00:00Z"))
                .andExpect(jsonPath("$[0].expiresOn").value(expires.toString()))
                .andExpect(jsonPath("$[0].daysLeft").value(30));
    }

    @Test
    void feedWithoutVersionsIsNewWithNullDates() throws Exception {
        feedList.add(TestEntities.feed(8L, "Fresh", "FreshCo"));

        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].status").value("new"))
                .andExpect(jsonPath("$[0].downloadedAt").value(nullValue()))
                .andExpect(jsonPath("$[0].expiresOn").value(nullValue()))
                .andExpect(jsonPath("$[0].daysLeft").value(nullValue()));
    }

    @Test
    void neverSucceededFeedWithAFailedAttemptIsFailed() throws Exception {
        Feed feed = TestEntities.feed(9L, "Broken", "BrokenCo");
        feedList.add(feed);
        latestVersions.put(9L, TestEntities.version(901L, feed, FeedVersion.FAILED, null, null));

        mvc.perform(get("/admin/feeds"))
                .andExpect(jsonPath("$[0].status").value("failed"))
                .andExpect(jsonPath("$[0].expiresOn").value(nullValue()));
    }
}
