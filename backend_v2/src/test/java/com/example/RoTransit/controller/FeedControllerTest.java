package com.example.RoTransit.controller;

import com.example.RoTransit.TestEntities;
import com.example.RoTransit.dto.FeedOperator;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import com.example.RoTransit.repository.OperatorRepository;
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
import static org.mockito.Mockito.times;
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
    private final FeedVersionRepository versions = mock(FeedVersionRepository.class);
    private final OperatorRepository operators = mock(OperatorRepository.class);
    private MockMvc mvc;
    private Path createdFile;
    private Path createdDir;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new FeedController(repo, versions, operators)).build();
    }

    @AfterEach
    void cleanUp() throws IOException {
        if (createdFile != null) {
            Files.deleteIfExists(createdFile);
        }
        if (createdDir != null) {
            Files.deleteIfExists(createdDir);
        }
    }

    private static Feed feed(long id) {
        return TestEntities.feed(id, "Testville", "TestCo");
    }

    /** Stubs feed {id} with a current version whose file_path is filePath. */
    private void currentFile(long id, String filePath) {
        Feed feed = feed(id);
        when(repo.findById(id)).thenReturn(Optional.of(feed));
        when(versions.findByFeedIdAndStatus(id, FeedVersion.CURRENT))
                .thenReturn(Optional.of(TestEntities.current(feed, filePath, null)));
    }

    @ParameterizedTest
    @ValueSource(strings = {"/etc/passwd", "feeds/../pom.xml", "feeds/../.env", "../.env", "pom.xml",
            "feeds/1/../../pom.xml", "feeds/1/../../.env"})
    void fileOutsideFeedsDirReturns404WithoutContent(String localPath) throws Exception {
        currentFile(1L, localPath);

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().string(""));
    }

    @Test
    void absolutePathEscapingFeedsDirReturns404() throws Exception {
        String escaping = FeedService.FEEDS_ROOT.toAbsolutePath().resolve("../pom.xml").toString();
        currentFile(1L, escaping);

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    void nullOrBlankFilePathReturns404(String localPath) throws Exception {
        currentFile(1L, localPath);

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void feedWithoutACurrentVersionReturns404() throws Exception {
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L)));
        when(versions.findByFeedIdAndStatus(1L, FeedVersion.CURRENT)).thenReturn(Optional.empty());

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void missingFileInsideFeedsDirReturns404() throws Exception {
        String missing = FeedService.FEEDS_ROOT.resolve("missing-" + UUID.randomUUID() + ".zip").toString();
        currentFile(1L, missing);

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void feedsDirItselfReturns404() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        currentFile(1L, FeedService.FEEDS_ROOT.toString());

        mvc.perform(get("/api/feeds/1/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void symlinkInsideFeedsDirPointingOutsideReturns404() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        createdFile = FeedService.FEEDS_ROOT.resolve("controller-test-" + UUID.randomUUID() + ".zip");
        Files.createSymbolicLink(createdFile, Path.of("pom.xml").toAbsolutePath());
        currentFile(1L, createdFile.toString());

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
        currentFile(2L, createdFile.toString());

        mvc.perform(get("/api/feeds/2/file"))
                .andExpect(status().isOk())
                .andExpect(content().contentType("application/zip"))
                // clients get "{id}.zip", whatever the file on disk is called
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"2.zip\""))
                .andExpect(content().bytes(bytes));
    }

    @Test
    void publicFeedListReturnsOnlySummaryFields() throws Exception {
        when(repo.findAll(Sort.by("id"))).thenReturn(List.of(feed(7L)));

        mvc.perform(get("/api/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0]", aMapWithSize(4)))
                .andExpect(jsonPath("$[0].id").value(7))
                .andExpect(jsonPath("$[0].cityName").value("Testville"))
                .andExpect(jsonPath("$[0].companyName").value("TestCo"))
                .andExpect(jsonPath("$[0].operators", hasSize(0)))
                .andExpect(jsonPath("$[0].localPath").doesNotExist());
    }

    @Test
    void publicFeedListAsksTheRepositoryForIdOrderAndKeepsIt() throws Exception {
        // the repository is responsible for the order; the controller must ask for it and not re-sort or use findAll()
        when(repo.findAll(Sort.by("id"))).thenReturn(List.of(feed(2L), feed(5L), feed(9L)));

        mvc.perform(get("/api/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].id", org.hamcrest.Matchers.contains(2, 5, 9)));

        ArgumentCaptor<Sort> sort = ArgumentCaptor.forClass(Sort.class);
        verify(repo).findAll(sort.capture());
        assertThat(sort.getValue()).isEqualTo(Sort.by("id"));
        assertThat(sort.getValue().getOrderFor("id").getDirection()).isEqualTo(Sort.Direction.ASC);
        verify(repo, never()).findAll();
    }

    @Test
    void operatorNamesAreGroupedPerFeedFromOneQuery() throws Exception {
        when(repo.findAll(Sort.by("id"))).thenReturn(List.of(feed(2L), feed(5L), feed(9L)));
        when(operators.findCurrentOperatorNames()).thenReturn(List.of(
                new FeedOperator(2L, "STB"), new FeedOperator(5L, "Metrorex"), new FeedOperator(2L, "Regio Bus")));

        mvc.perform(get("/api/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].operators", org.hamcrest.Matchers.contains("STB", "Regio Bus")))
                .andExpect(jsonPath("$[1].operators", org.hamcrest.Matchers.contains("Metrorex")))
                .andExpect(jsonPath("$[2].operators", hasSize(0))); // no current version / no agency.txt

        // one query for all feeds, not one per feed (N+1)
        verify(operators, times(1)).findCurrentOperatorNames();
    }

    // ---- versioned files: feeds/{id}/{sha256}.zip ----

    @Test
    void nestedVersionFileIsServed() throws Exception {
        createdDir = Files.createDirectories(FeedService.FEEDS_ROOT.resolve("controller-test-" + UUID.randomUUID()));
        createdFile = createdDir.resolve("0123abcd.zip");
        byte[] bytes = "PK-nested".getBytes(StandardCharsets.UTF_8);
        Files.write(createdFile, bytes);
        currentFile(3L, createdFile.toString());

        mvc.perform(get("/api/feeds/3/file"))
                .andExpect(status().isOk())
                .andExpect(content().contentType("application/zip"))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"3.zip\""))
                .andExpect(content().bytes(bytes));
    }

    @Test
    void missingNestedVersionFileReturns404() throws Exception {
        // e.g. retention or someone deleted it while the row still points at it
        currentFile(3L, FeedService.FEEDS_ROOT.resolve("3").resolve("missing-" + UUID.randomUUID() + ".zip").toString());

        mvc.perform(get("/api/feeds/3/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION));
    }

    @Test
    void nestedFolderThatIsASymlinkToOutsideReturns404() throws Exception {
        // feeds/<x> -> the project folder: feeds/<x>/pom.xml looks nested but really is outside feeds/
        Files.createDirectories(FeedService.FEEDS_ROOT);
        createdFile = FeedService.FEEDS_ROOT.resolve("controller-test-" + UUID.randomUUID());
        Files.createSymbolicLink(createdFile, Path.of("").toAbsolutePath());
        currentFile(3L, createdFile.resolve("pom.xml").toString());

        mvc.perform(get("/api/feeds/3/file"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(content().string(""));
    }
}
