package com.example.RoTransit.controller;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThat;
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
    private final FeedService feedService = mock(FeedService.class);
    private final FeedUpdateJob feedUpdateJob = mock(FeedUpdateJob.class);
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new AdminController(repo, feedService, feedUpdateJob)).build();
    }

    private Feed feed(long id, String localPath) {
        Feed feed = new Feed();
        ReflectionTestUtils.setField(feed, "id", id);
        feed.setCityName("Testville");
        feed.setCompanyName("TestCo");
        feed.setSourceId("mdb-test");
        feed.setStatus("downloaded");
        feed.setLocalPath(localPath);
        return feed;
    }

    private Feed feed(long id, String city, LocalDate expiresOn) {
        Feed feed = feed(id, "feeds/" + id + ".zip");
        feed.setCityName(city);
        feed.setCompanyName(city + "Co");
        feed.setExpiresOn(expiresOn);
        feed.setDownloadedAt(Instant.parse("2026-10-0" + (id % 9 + 1) + "T08:00:00Z"));
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
    void createFeedIgnoresLocalPathAndStatusFromRequestBody() throws Exception {
        when(repo.save(any(Feed.class))).thenAnswer(inv -> {
            Feed saved = inv.getArgument(0);
            ReflectionTestUtils.setField(saved, "id", 42L);
            return saved;
        });

        mvc.perform(post("/admin/feeds")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"cityName":"Probe","companyName":"ProbeCo","sourceId":"mdb-probe",
                                 "localPath":"/etc/passwd","status":"hacked","id":5}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(42))
                .andExpect(jsonPath("$.cityName").value("Probe"))
                .andExpect(jsonPath("$.companyName").value("ProbeCo"))
                .andExpect(jsonPath("$.sourceId").value("mdb-probe"))
                .andExpect(jsonPath("$.status").value("new"))
                .andExpect(jsonPath("$.localPath").doesNotExist());

        ArgumentCaptor<Feed> captor = ArgumentCaptor.forClass(Feed.class);
        verify(repo).save(captor.capture());
        Feed saved = captor.getValue();
        assertThat(saved.getLocalPath()).isNull();
        assertThat(saved.getStatus()).isEqualTo("new"); // entity default, not the "hacked" value from the body
        assertThat(saved.getSourceId()).isEqualTo("mdb-probe");
        assertThat(saved.getDownloadedAt()).isNotNull();
    }

    @Test
    void feedJsonNeverExposesLocalPath() throws Exception {
        when(repo.findById(3L)).thenReturn(Optional.of(feed(3L, "feeds/3.zip")));
        when(repo.findAll()).thenReturn(List.of(feed(3L, "feeds/3.zip")));

        mvc.perform(get("/admin/feeds/3"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(3))
                .andExpect(jsonPath("$.localPath").doesNotExist());
        // GET /feeds is gone; the admin list (FeedStatus) is the replacement
        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].localPath").doesNotExist());
    }

    // ---- download / expires ----

    @Test
    void downloadReturnsTheSavedFeedWithoutLocalPath() throws Exception {
        Feed downloaded = feed(4L, "feeds/4.zip");
        downloaded.setExpiresOn(LocalDate.of(2027, 12, 31));
        when(feedService.download(4L)).thenReturn(downloaded);

        mvc.perform(post("/admin/feeds/4/download"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(4))
                .andExpect(jsonPath("$.status").value("downloaded"))
                .andExpect(jsonPath("$.expiresOn").value("2027-12-31"))
                .andExpect(jsonPath("$.localPath").doesNotExist());
        verify(feedService).download(4L);
    }

    @Test
    void downloadBadGatewayFromTheSourceStays502() throws Exception {
        when(feedService.download(5L)).thenThrow(new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "source returned 403 for https://files.mobilitydatabase.org/mdb-x/latest.zip"));

        mvc.perform(post("/admin/feeds/5/download"))
                .andExpect(status().isBadGateway());
        verify(repo, never()).save(any());
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
        Feed f = feed(7L, "Sibiu", today.plusDays(30));
        f.setStatus("downloaded");
        f.setSourceUrl("https://files.mobilitydatabase.org/mdb-7/latest.zip");
        when(repo.findAll()).thenReturn(List.of(f));

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
        when(repo.findAll()).thenReturn(List.of(
                feed(1L, "Future", today.plusDays(400)),
                feed(2L, "Today", today),
                feed(3L, "Past", today.minusDays(3)),
                feed(4L, "Unknown", null)));

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
    void statusListIsNullsFirstThenExpiresOnAscendingWithTiesKeptInRepositoryOrder() throws Exception {
        LocalDate today = LocalDate.now();
        when(repo.findAll()).thenReturn(List.of(
                feed(1L, "A", today.plusDays(10)),
                feed(2L, "B", null),
                feed(3L, "C", today.minusDays(3)),
                feed(4L, "D", today.plusDays(10)),
                feed(5L, "E", null),
                feed(6L, "F", today),
                feed(7L, "G", today.plusDays(2))));

        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(7)))
                .andExpect(jsonPath("$[*].id", contains(2, 5, 3, 6, 7, 1, 4)))
                .andExpect(jsonPath("$[*].daysLeft", contains(null, null, -3, 0, 2, 10, 10)));
        verifyNoInteractions(feedService, feedUpdateJob);
    }

    @Test
    void emptyRepositoryGivesEmptyStatusList() throws Exception {
        when(repo.findAll()).thenReturn(List.of());

        mvc.perform(get("/admin/feeds"))
                .andExpect(status().isOk())
                .andExpect(content().json("[]"));
    }
}
