package com.example.RoTransit.controller;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpHeaders;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.hamcrest.Matchers.aMapWithSize;
import static org.hamcrest.Matchers.hasSize;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Standalone MockMvc tests for the public FeedController (/api/feeds, /api/feeds/{id}/file).
 * No Spring context, no DB, no network. The admin routes are covered by AdminControllerTest.
 * Note: the "valid zip" test writes one uniquely named file into FeedService.FEEDS_ROOT (./feeds) and deletes it afterwards.
 */
class FeedControllerTest {

    private final FeedRepository repo = mock(FeedRepository.class);
    private MockMvc mvc;
    private Path createdFile;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new FeedController(repo)).build();
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

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().string(""));
    }

    @Test
    void absolutePathEscapingFeedsDirReturns404() throws Exception {
        String escaping = FeedService.FEEDS_ROOT.toAbsolutePath().resolve("../pom.xml").toString();
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, escaping)));

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    void nullOrBlankLocalPathReturns404(String localPath) throws Exception {
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, localPath)));

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void missingFileInsideFeedsDirReturns404() throws Exception {
        String missing = FeedService.FEEDS_ROOT.resolve("missing-" + UUID.randomUUID() + ".zip").toString();
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, missing)));

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void feedsDirItselfReturns404() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, FeedService.FEEDS_ROOT.toString())));

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void symlinkInsideFeedsDirPointingOutsideReturns404() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        createdFile = FeedService.FEEDS_ROOT.resolve("controller-test-" + UUID.randomUUID() + ".zip");
        Files.createSymbolicLink(createdFile, Path.of("pom.xml").toAbsolutePath());
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, createdFile.toString())));

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().string(""));
    }

    @Test
    void zipInsideFeedsDirIsServedAsAttachment() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        String name = "controller-test-" + UUID.randomUUID() + ".zip";
        createdFile = FeedService.FEEDS_ROOT.resolve(name);
        byte[] bytes = "PK-not-really-a-zip".getBytes(StandardCharsets.UTF_8);
        Files.write(createdFile, bytes);
        when(repo.findById(2L)).thenReturn(Optional.of(feed(2L, createdFile.toString())));

        mvc.perform(get("/api/feeds/2/file"))
                .andExpect(status().isOk())
                .andExpect(content().contentType("application/zip"))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + name + "\""))
                .andExpect(content().bytes(bytes));
    }

    @Test
    void publicFeedListReturnsOnlySummaryFields() throws Exception {
        when(repo.findAll(Sort.by("id"))).thenReturn(List.of(feed(7L, "feeds/7.zip")));

        mvc.perform(get("/api/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0]", aMapWithSize(3)))
                .andExpect(jsonPath("$[0].id").value(7))
                .andExpect(jsonPath("$[0].cityName").value("Testville"))
                .andExpect(jsonPath("$[0].companyName").value("TestCo"))
                .andExpect(jsonPath("$[0].localPath").doesNotExist());
    }

    @Test
    void publicFeedListAsksTheRepositoryForIdOrderAndKeepsIt() throws Exception {
        // the repository is responsible for the order; the controller must ask for it and not re-sort or use findAll()
        when(repo.findAll(Sort.by("id"))).thenReturn(List.of(feed(2L, "feeds/2.zip"), feed(5L, null), feed(9L, null)));

        mvc.perform(get("/api/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].id", org.hamcrest.Matchers.contains(2, 5, 9)));

        ArgumentCaptor<Sort> sort = ArgumentCaptor.forClass(Sort.class);
        verify(repo).findAll(sort.capture());
        assertThat(sort.getValue()).isEqualTo(Sort.by("id"));
        assertThat(sort.getValue().getOrderFor("id").getDirection()).isEqualTo(Sort.Direction.ASC);
        verify(repo, never()).findAll();
    }
}
