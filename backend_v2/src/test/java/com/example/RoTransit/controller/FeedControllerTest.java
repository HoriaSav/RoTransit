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
 * Standalone MockMvc tests for the public FeedController (/api/feeds, /api/feeds/{id}/file, .../file/upcoming).
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
                .andExpect(jsonPath("$[0]", aMapWithSize(6)))
                .andExpect(jsonPath("$[0].id").value(7))
                .andExpect(jsonPath("$[0].cityName").value("Testville"))
                .andExpect(jsonPath("$[0].companyName").value("TestCo"))
                .andExpect(jsonPath("$[0].operators", hasSize(0)))
                .andExpect(jsonPath("$[0].current").value(org.hamcrest.Matchers.nullValue()))
                .andExpect(jsonPath("$[0].upcoming").value(org.hamcrest.Matchers.nullValue()))
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

    // ---- upcoming versions and ETag ----

    /** A real file in feeds/{id}/ for a version with the given status and sha256; returns the version. */
    private FeedVersion versionFile(long id, String status, String sha256) throws IOException {
        Feed feed = feed(id);
        createdDir = FeedService.FEEDS_ROOT.resolve(String.valueOf(id));
        Files.createDirectories(createdDir);
        createdFile = Files.writeString(createdDir.resolve(sha256 + ".zip"), status + " bytes");
        FeedVersion version = TestEntities.version(id * 10, feed, status, createdFile.toString(), null);
        version.setSha256(sha256);
        when(repo.findById(id)).thenReturn(Optional.of(feed));
        when(versions.findByFeedIdAndStatus(id, status)).thenReturn(Optional.of(version));
        return version;
    }

    @Test
    void feedListShowsCurrentAndUpcomingVersionInfoFromTwoQueries() throws Exception {
        Feed withBoth = feed(3L), withCurrentOnly = feed(4L);
        FeedVersion current = TestEntities.current(withBoth, "feeds/3/aaa.zip", java.time.LocalDate.of(2026, 12, 31));
        current.setSha256("aaa");
        current.setStartsOn(java.time.LocalDate.of(2026, 9, 1));
        FeedVersion upcoming = TestEntities.version(301, withBoth, FeedVersion.UPCOMING, "feeds/3/bbb.zip",
                java.time.LocalDate.of(2027, 3, 31));
        upcoming.setSha256("bbb");
        upcoming.setStartsOn(java.time.LocalDate.of(2026, 11, 1));
        FeedVersion onlyCurrent = TestEntities.current(withCurrentOnly, "feeds/4/ccc.zip", null);
        onlyCurrent.setSha256("ccc");
        when(repo.findAll(Sort.by("id"))).thenReturn(List.of(withBoth, withCurrentOnly));
        when(versions.findCurrentByFeedId()).thenReturn(java.util.Map.of(3L, current, 4L, onlyCurrent));
        when(versions.findUpcomingByFeedId()).thenReturn(java.util.Map.of(3L, upcoming));

        mvc.perform(get("/api/feeds"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].current.sha256").value("aaa"))
                .andExpect(jsonPath("$[0].current.startsOn").value("2026-09-01"))
                .andExpect(jsonPath("$[0].current.expiresOn").value("2026-12-31"))
                .andExpect(jsonPath("$[0].current.downloadedAt").exists())
                .andExpect(jsonPath("$[0].current.filePath").doesNotExist())
                .andExpect(jsonPath("$[0].upcoming.sha256").value("bbb"))
                .andExpect(jsonPath("$[0].upcoming.startsOn").value("2026-11-01"))
                .andExpect(jsonPath("$[1].current.sha256").value("ccc"))
                .andExpect(jsonPath("$[1].upcoming").value(org.hamcrest.Matchers.nullValue()));

        // the maps are loaded once for the whole list, not per feed
        verify(versions, times(1)).findCurrentByFeedId();
        verify(versions, times(1)).findUpcomingByFeedId();
        verify(versions, never()).findByFeedIdAndStatus(org.mockito.ArgumentMatchers.anyLong(),
                org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void currentFileHasTheShaAsETagAndAMatchingIfNoneMatchGives304WithoutBody() throws Exception {
        versionFile(5L, FeedVersion.CURRENT, "abc123");

        mvc.perform(get("/api/feeds/5/file"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ETAG, "\"abc123\""))
                .andExpect(content().string("current bytes"));

        mvc.perform(get("/api/feeds/5/file").header(HttpHeaders.IF_NONE_MATCH, "\"abc123\""))
                .andExpect(status().isNotModified())
                .andExpect(header().string(HttpHeaders.ETAG, "\"abc123\""))
                .andExpect(content().string(""));
    }

    @Test
    void anOtherETagGetsTheWholeFile() throws Exception {
        versionFile(5L, FeedVersion.CURRENT, "abc123");

        mvc.perform(get("/api/feeds/5/file").header(HttpHeaders.IF_NONE_MATCH, "\"old-sha\""))
                .andExpect(status().isOk())
                .andExpect(content().string("current bytes"));
    }

    @Test
    void upcomingFileIsServedWithItsOwnNameAndETagAnd304() throws Exception {
        versionFile(6L, FeedVersion.UPCOMING, "def456");

        mvc.perform(get("/api/feeds/6/file/upcoming"))
                .andExpect(status().isOk())
                .andExpect(content().contentType("application/zip"))
                .andExpect(header().string(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"6-upcoming.zip\""))
                .andExpect(header().string(HttpHeaders.ETAG, "\"def456\""))
                .andExpect(content().string("upcoming bytes"));

        mvc.perform(get("/api/feeds/6/file/upcoming").header(HttpHeaders.IF_NONE_MATCH, "\"def456\""))
                .andExpect(status().isNotModified())
                .andExpect(content().string(""));
    }

    @Test
    void upcomingFileReturns404WhenThereIsNone() throws Exception {
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L)));
        when(versions.findByFeedIdAndStatus(1L, FeedVersion.UPCOMING)).thenReturn(Optional.empty());

        mvc.perform(get("/api/feeds/1/file/upcoming"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.CONTENT_DISPOSITION))
                .andExpect(header().doesNotExist(HttpHeaders.ETAG));
    }

    @Test
    void upcomingFileOutsideFeedsDirReturns404() throws Exception {
        Feed feed = feed(1L);
        when(repo.findById(1L)).thenReturn(Optional.of(feed));
        when(versions.findByFeedIdAndStatus(1L, FeedVersion.UPCOMING))
                .thenReturn(Optional.of(TestEntities.version(1, feed, FeedVersion.UPCOMING, "feeds/1/../../pom.xml", null)));

        mvc.perform(get("/api/feeds/1/file/upcoming"))
                .andExpect(status().isNotFound())
                .andExpect(content().string(""));
    }

    @Test
    void currentFileStillServesTheCurrentWhenThereIsAlsoAnUpcoming() throws Exception {
        versionFile(7L, FeedVersion.CURRENT, "cur");

        mvc.perform(get("/api/feeds/7/file"))
                .andExpect(status().isOk())
                .andExpect(content().string("current bytes"));
        verify(versions, never()).findByFeedIdAndStatus(7L, FeedVersion.UPCOMING);
    }
}
