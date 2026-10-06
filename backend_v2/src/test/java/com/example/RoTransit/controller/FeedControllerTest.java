package com.example.RoTransit.controller;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.aMapWithSize;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Standalone MockMvc tests for FeedController (no Spring context, no DB, no network).
 * Note: the "valid zip" test writes one uniquely named file into FeedService.FEEDS_ROOT (./feeds) and deletes it afterwards.
 */
class FeedControllerTest {

    private final FeedRepository repo = mock(FeedRepository.class);
    private final FeedService feedService = mock(FeedService.class);
    private final FeedUpdateJob feedUpdateJob = mock(FeedUpdateJob.class);
    private MockMvc mvc;
    private Path createdFile;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new FeedController(repo, feedUpdateJob, feedService)).build();
    }

    @AfterEach
    void cleanUp() throws IOException {
        if (createdFile != null) {
            Files.deleteIfExists(createdFile);
        }
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

    @ParameterizedTest
    @ValueSource(strings = {"/etc/passwd", "feeds/../pom.xml", "feeds/../.env", "../.env", "pom.xml"})
    void fileOutsideFeedsDirReturns404WithoutContent(String localPath) throws Exception {
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, localPath)));

        mvc.perform(get("/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().string(""));
    }

    @Test
    void absolutePathEscapingFeedsDirReturns404() throws Exception {
        String escaping = FeedService.FEEDS_ROOT.toAbsolutePath().resolve("../pom.xml").toString();
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, escaping)));

        mvc.perform(get("/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    void nullOrBlankLocalPathReturns404(String localPath) throws Exception {
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, localPath)));

        mvc.perform(get("/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void missingFileInsideFeedsDirReturns404() throws Exception {
        String missing = FeedService.FEEDS_ROOT.resolve("missing-" + UUID.randomUUID() + ".zip").toString();
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, missing)));

        mvc.perform(get("/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void feedsDirItselfReturns404() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, FeedService.FEEDS_ROOT.toString())));

        mvc.perform(get("/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void symlinkInsideFeedsDirPointingOutsideReturns404() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        createdFile = FeedService.FEEDS_ROOT.resolve("controller-test-" + UUID.randomUUID() + ".zip");
        Files.createSymbolicLink(createdFile, Path.of("pom.xml").toAbsolutePath());
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, createdFile.toString())));

        mvc.perform(get("/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().string(""));
    }

    @Test
    @SuppressWarnings("unchecked")
    void updateStreamsPlainTextLines() throws Exception {
        doAnswer(inv -> {
            Consumer<String> onResult = inv.getArgument(0);
            onResult.accept("Brasov is up to date!");
            onResult.accept("Cluj-Napoca has been updated!");
            return null;
        }).when(feedUpdateJob).updateFeeds(any(Consumer.class));

        MvcResult result = mvc.perform(post("/feeds/update"))
                .andExpect(request().asyncStarted())
                .andReturn();

        mvc.perform(asyncDispatch(result))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_PLAIN))
                .andExpect(content().string("Brasov is up to date!\nCluj-Napoca has been updated!\n"));
    }

    @Test
    void zipInsideFeedsDirIsServedAsAttachment() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        String name = "controller-test-" + UUID.randomUUID() + ".zip";
        createdFile = FeedService.FEEDS_ROOT.resolve(name);
        byte[] bytes = "PK-not-really-a-zip".getBytes(StandardCharsets.UTF_8);
        Files.write(createdFile, bytes);
        when(repo.findById(2L)).thenReturn(Optional.of(feed(2L, createdFile.toString())));

        mvc.perform(get("/feeds/2/file"))
                .andExpect(status().isOk())
                .andExpect(content().contentType("application/zip"))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + name + "\""))
                .andExpect(content().bytes(bytes));
    }

    @Test
    void createFeedIgnoresLocalPathAndStatusFromRequestBody() throws Exception {
        when(repo.save(any(Feed.class))).thenAnswer(inv -> {
            Feed saved = inv.getArgument(0);
            ReflectionTestUtils.setField(saved, "id", 42L);
            return saved;
        });

        mvc.perform(post("/feeds")
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
                .andExpect(jsonPath("$.localPath").doesNotExist());

        ArgumentCaptor<Feed> captor = ArgumentCaptor.forClass(Feed.class);
        verify(repo).save(captor.capture());
        Feed saved = captor.getValue();
        assertThat(saved.getLocalPath()).isNull();
        assertThat(saved.getStatus()).isNull();
        assertThat(saved.getSourceId()).isEqualTo("mdb-probe");
        assertThat(saved.getDownloadedAt()).isNotNull();
    }

    @Test
    void feedJsonNeverExposesLocalPath() throws Exception {
        when(repo.findById(3L)).thenReturn(Optional.of(feed(3L, "feeds/3.zip")));
        when(repo.findAll()).thenReturn(List.of(feed(3L, "feeds/3.zip")));

        mvc.perform(get("/feeds/3"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(3))
                .andExpect(jsonPath("$.localPath").doesNotExist());
        mvc.perform(get("/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].localPath").doesNotExist());
    }

    @Test
    void publicFeedListReturnsOnlySummaryFields() throws Exception {
        when(repo.findAll()).thenReturn(List.of(feed(7L, "feeds/7.zip")));

        mvc.perform(get("/api/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0]", aMapWithSize(3)))
                .andExpect(jsonPath("$[0].id").value(7))
                .andExpect(jsonPath("$[0].cityName").value("Testville"))
                .andExpect(jsonPath("$[0].companyName").value("TestCo"));
    }
}
