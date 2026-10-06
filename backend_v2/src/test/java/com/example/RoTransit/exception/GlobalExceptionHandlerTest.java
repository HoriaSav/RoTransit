package com.example.RoTransit.exception;

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
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
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
                .standaloneSetup(new FeedController(repo, mock(FeedUpdateJob.class), realService))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    @ParameterizedTest
    @CsvSource({
            "GET,  /feeds/999999",
            "GET,  /feeds/999999/file",
            "GET,  /feeds/999999/expires",
            "POST, /feeds/999999/download",
            "GET,  /feeds/0",
            "POST, /feeds/-1/download"
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
        mvc.perform(request(org.springframework.http.HttpMethod.POST, "/feeds/987654/download"))
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
                .standaloneSetup(new FeedController(repo, mock(FeedUpdateJob.class), service))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc502.perform(request(org.springframework.http.HttpMethod.POST, "/feeds/5/download"))
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
                .standaloneSetup(new FeedController(repo, mock(FeedUpdateJob.class), service))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        mvc502.perform(request(org.springframework.http.HttpMethod.POST, "/feeds/5/download"))
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
                .standaloneSetup(new FeedController(repo, mock(FeedUpdateJob.class), service))
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        // not handled by the advice: propagates (500 in the real app), it is not swallowed into a 404
        assertThatThrownBy(() -> mvcIse.perform(get("/feeds/5/expires")))
                .hasRootCauseInstanceOf(IllegalStateException.class);
    }
}
