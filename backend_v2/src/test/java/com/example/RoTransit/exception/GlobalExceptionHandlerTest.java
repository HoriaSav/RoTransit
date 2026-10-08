package com.example.RoTransit.exception;

import com.example.RoTransit.controller.AdminController;
import com.example.RoTransit.controller.FeedController;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.aMapWithSize;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * GlobalExceptionHandler wired into a standalone MockMvc (no Spring context, no DB, no network).
 * The real FeedService is used with a mocked repository, so the unknown-id path runs the real
 * findById(..).orElseThrow() in both the controller and the service.
 */
class GlobalExceptionHandlerTest {

    private final FeedRepository repo = mock(FeedRepository.class);
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        when(repo.findById(anyLong())).thenReturn(Optional.empty());
        FeedService realService = new FeedService(repo);
        mvc = MockMvcBuilders
                .standaloneSetup(new FeedController(repo), new AdminController(repo, realService, mock(FeedUpdateJob.class)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    @ParameterizedTest
    @CsvSource({
            "GET,  /admin/feeds/999999",
            "GET,  /api/feeds/999999/file",
            "GET,  /admin/feeds/999999/expires",
            "POST, /admin/feeds/999999/download",
            "GET,  /admin/feeds/0",
            "POST, /admin/feeds/-1/download"
    })
    void unknownIdIsProblemDetail404(String method, String path) throws Exception {
        mvc.perform(request(org.springframework.http.HttpMethod.valueOf(method), path))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.title").value("Not Found"))
                .andExpect(jsonPath("$.detail").value("Feed not found"));
    }

    @Test
    void unknownIdDownloadCreatesNoFiles() throws Exception {
        mvc.perform(request(org.springframework.http.HttpMethod.POST, "/admin/feeds/987654/download"))
                .andExpect(status().isNotFound());

        assertThat(FeedService.FEEDS_ROOT.resolve("987654.zip")).doesNotExist();
        if (java.nio.file.Files.isDirectory(FeedService.FEEDS_ROOT)) {
            try (var files = java.nio.file.Files.list(FeedService.FEEDS_ROOT)) {
                assertThat(files.map(p -> p.getFileName().toString()))
                        .noneMatch(name -> name.startsWith("987654-"));
            }
        }
    }

    @Test
    void badGatewayFromDownloadIsNotTurnedInto404() throws Exception {
        FeedService service = mock(FeedService.class);
        when(service.download(5L)).thenThrow(new ResponseStatusException(HttpStatus.BAD_GATEWAY, "source returned 403"));
        MockMvc mvc502 = MockMvcBuilders
                .standaloneSetup(new AdminController(repo, service, mock(FeedUpdateJob.class)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc502.perform(request(org.springframework.http.HttpMethod.POST, "/admin/feeds/5/download"))
                .andExpect(status().isBadGateway());
    }

    @Test
    void invalidZipBadGatewayWithZipExceptionCauseStays502() throws Exception {
        // the exact exception FeedService.download throws for a 200 body that is not a zip
        FeedService service = mock(FeedService.class);
        when(service.download(5L)).thenThrow(new ResponseStatusException(HttpStatus.BAD_GATEWAY,
                "source sent an invalid zip for https://files.mobilitydatabase.org/mdb-x/latest.zip",
                new java.util.zip.ZipException("zip END header not found")));
        MockMvc mvc502 = MockMvcBuilders
                .standaloneSetup(new AdminController(repo, service, mock(FeedUpdateJob.class)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc502.perform(request(org.springframework.http.HttpMethod.POST, "/admin/feeds/5/download"))
                .andExpect(status().isBadGateway())
                .andExpect(result -> assertThat(result.getResolvedException())
                        .isInstanceOf(ResponseStatusException.class)
                        .hasCauseInstanceOf(java.util.zip.ZipException.class));
    }

    @Test
    void otherExceptionsAreNotMappedTo404() throws Exception {
        FeedService service = mock(FeedService.class);
        when(service.getExpireDate(5L)).thenThrow(new IllegalStateException("feed_info.txt is missing"));
        MockMvc mvcIse = MockMvcBuilders
                .standaloneSetup(new AdminController(repo, service, mock(FeedUpdateJob.class)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        // not handled by the advice: propagates (500 in the real app), it is not swallowed into a 404
        assertThatThrownBy(() -> mvcIse.perform(get("/admin/feeds/5/expires")))
                .hasRootCauseInstanceOf(IllegalStateException.class);
    }

    // ---- ResponseEntityExceptionHandler: framework errors are problem+json too (standalone, no Boot error page) ----

    private static org.springframework.test.web.servlet.ResultMatcher[] problem(int status, String title, String instance) {
        return new org.springframework.test.web.servlet.ResultMatcher[]{
                status().is(status),
                content().contentType(MediaType.APPLICATION_PROBLEM_JSON),
                jsonPath("$.status").value(status),
                jsonPath("$.title").value(title),
                jsonPath("$.instance").value(instance),
                jsonPath("$.detail").isNotEmpty(),
                jsonPath("$.path").doesNotExist(),
                jsonPath("$.timestamp").doesNotExist()};
    }

    @Test
    void malformedJsonIs400ProblemJson() throws Exception {
        mvc.perform(post("/admin/feeds").contentType(MediaType.APPLICATION_JSON).content("{\"cityName\": "))
                .andExpectAll(problem(400, "Bad Request", "/admin/feeds"))
                .andExpect(jsonPath("$.detail").value("Failed to read request"));
        verify(repo, never()).save(any());
    }

    @Test
    void wrongMethodIs405ProblemJsonWithAllowHeader() throws Exception {
        mvc.perform(request(org.springframework.http.HttpMethod.DELETE, "/admin/feeds"))
                .andExpectAll(problem(405, "Method Not Allowed", "/admin/feeds"))
                .andExpect(header().string("Allow", containsString("GET")))
                .andExpect(header().string("Allow", containsString("POST")))
                .andExpect(jsonPath("$.detail").value("Method 'DELETE' is not supported."));
    }

    @Test
    void wrongContentTypeIs415ProblemJson() throws Exception {
        mvc.perform(post("/admin/feeds").contentType(MediaType.TEXT_PLAIN).content("cityName=x"))
                .andExpectAll(problem(415, "Unsupported Media Type", "/admin/feeds"))
                .andExpect(jsonPath("$.detail").value(containsString("Content-Type 'text/plain")));
        verify(repo, never()).save(any());
    }

    @Test
    void nonNumericIdIs400ProblemJson() throws Exception {
        mvc.perform(get("/admin/feeds/abc"))
                .andExpectAll(problem(400, "Bad Request", "/admin/feeds/abc"))
                .andExpect(jsonPath("$.detail").value("Failed to convert 'id' with value: 'abc'"));
        mvc.perform(get("/api/feeds/abc/file"))
                .andExpectAll(problem(400, "Bad Request", "/api/feeds/abc/file"));
        verify(repo, never()).findById(anyLong());
    }

    @Test
    void responseStatusException502IsProblemJsonWithTheReasonAsDetail() throws Exception {
        FeedService service = mock(FeedService.class);
        when(service.download(5L)).thenThrow(new ResponseStatusException(HttpStatus.BAD_GATEWAY, "source returned 403 for https://files.mobilitydatabase.org/mdb-x/latest.zip"));
        MockMvc mvc502 = MockMvcBuilders
                .standaloneSetup(new AdminController(repo, service, mock(FeedUpdateJob.class)))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc502.perform(request(org.springframework.http.HttpMethod.POST, "/admin/feeds/5/download"))
                .andExpectAll(problem(502, "Bad Gateway", "/admin/feeds/5/download"))
                // note: the reason, including the upstream URL, is exposed as detail
                .andExpect(jsonPath("$.detail").value("source returned 403 for https://files.mobilitydatabase.org/mdb-x/latest.zip"));
    }

    @Test
    void responseStatusException404WithoutReasonIsProblemJson() throws Exception {
        com.example.RoTransit.entity.Feed noFile = new com.example.RoTransit.entity.Feed();
        org.springframework.test.util.ReflectionTestUtils.setField(noFile, "id", 7L);
        when(repo.findById(7L)).thenReturn(Optional.of(noFile)); // localPath null -> ResponseStatusException(NOT_FOUND)

        mvc.perform(get("/api/feeds/7/file"))
                .andExpect(status().isNotFound())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.title").value("Not Found"))
                .andExpect(jsonPath("$.instance").value("/api/feeds/7/file"))
                .andExpect(jsonPath("$.path").doesNotExist());
    }

    @Test
    void noSuchElement404IsUnchanged() throws Exception {
        mvc.perform(get("/admin/feeds/999999"))
                .andExpectAll(problem(404, "Not Found", "/admin/feeds/999999"))
                .andExpect(jsonPath("$.detail").value("Feed not found"))
                .andExpect(jsonPath("$", aMapWithSize(4))); // title, status, detail, instance (type=about:blank omitted)
    }
}
