package com.example.RoTransit.config;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * SecurityConfig against the REAL filter chain on a real Tomcat (random port), driven by java.net.http.HttpClient
 * (no cookie handler, no redirects), so error dispatches to /error and response headers are exactly what a client sees.
 * FeedRepository, FeedService and FeedUpdateJob are mocks: nothing is read from or written to the DB, nothing downloads.
 * The admin password is the test-only value from src/test/resources/config/application.properties.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SecurityConfigTest {

    @Value("${local.server.port}")
    private int port;

    @Value("${spring.security.user.name}")
    private String adminUser;

    @Value("${spring.security.user.password}")
    private String adminPassword;

    @MockitoBean
    private FeedRepository repo;

    @MockitoBean
    private FeedService feedService;

    @MockitoBean
    private FeedUpdateJob feedUpdateJob;

    private final HttpClient http = HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NEVER).build();
    private Path servedFile;

    @BeforeEach
    void stubs() throws Exception {
        when(repo.findById(1L)).thenReturn(Optional.of(feed(1L, null)));
        when(repo.findAll()).thenReturn(List.of(feed(1L, null)));               // AdminController sorts in memory
        when(repo.findAll(Sort.by("id"))).thenReturn(List.of(feed(1L, null)));  // FeedController asks the DB for id order
        when(repo.save(any(Feed.class))).thenAnswer(inv -> inv.getArgument(0));
        when(feedService.getExpireDate(1L)).thenReturn(LocalDate.of(2027, 12, 9));
        when(feedService.download(1L)).thenReturn(feed(1L, null));
    }

    @AfterEach
    void cleanUp() throws Exception {
        if (servedFile != null) Files.deleteIfExists(servedFile);
    }

    private static Feed feed(long id, String localPath) {
        Feed feed = new Feed();
        ReflectionTestUtils.setField(feed, "id", id);
        feed.setCityName("Testville");
        feed.setCompanyName("TestCo");
        feed.setSourceId("mdb-test");
        feed.setStatus("downloaded");
        feed.setLocalPath(localPath);
        return feed;
    }

    private String basic(String user, String password) {
        return "Basic " + Base64.getEncoder().encodeToString((user + ":" + password).getBytes(StandardCharsets.UTF_8));
    }

    private String admin() {
        return basic(adminUser, adminPassword);
    }

    private HttpResponse<byte[]> call(String method, String path, String authorization) throws Exception {
        return method.equals("POST")
                ? send(method, path, authorization, "application/json", "{\"cityName\":\"SecProbe\",\"companyName\":\"SecCo\",\"sourceId\":\"mdb-sec\"}")
                : send(method, path, authorization, null, null);
    }

    private HttpResponse<byte[]> send(String method, String path, String authorization, String contentType, String requestBody) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path));
        b.method(method, requestBody == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(requestBody));
        if (contentType != null) b.header("Content-Type", contentType);
        if (authorization != null) b.header("Authorization", authorization);
        HttpResponse<byte[]> response = http.send(b.build(), HttpResponse.BodyHandlers.ofByteArray());
        // stateless: no response may ever try to start a session
        assertThat(response.headers().allValues("Set-Cookie")).as("Set-Cookie on %s %s", method, path).isEmpty();
        return response;
    }

    private static String body(HttpResponse<byte[]> r) {
        return new String(r.body(), StandardCharsets.UTF_8);
    }

    // ---- /admin/** ----

    @ParameterizedTest(name = "{0} {1}")
    @CsvSource({"GET, /admin/feeds", "GET, /admin/feeds/1", "GET, /admin/feeds/1/expires",
            "POST, /admin/feeds/update", "POST, /admin/feeds", "POST, /admin/feeds/1/download"})
    void adminRoutesWithoutValidCredentialsAre401WithBasicChallengeAndDoNothing(String method, String path) throws Exception {
        for (String auth : new String[]{null, basic(adminUser, "wrong-" + adminPassword), basic("nobody", adminPassword), "Bearer abc"}) {
            HttpResponse<byte[]> r = call(method, path, auth);
            assertThat(r.statusCode()).as("%s %s with %s", method, path, auth).isEqualTo(401);
            assertThat(r.headers().firstValue("WWW-Authenticate")).as("challenge for %s", auth).hasValueSatisfying(v -> assertThat(v).startsWith("Basic realm="));
        }
        verifyNoInteractions(feedService, feedUpdateJob);
        verify(repo, never()).save(any());
        verify(repo, never()).findById(any());
        verify(repo, never()).findAll();
        verify(repo, never()).findAll(any(Sort.class));
    }

    @Test
    void adminReadRoutesWorkWithTheRightPassword() throws Exception {
        HttpResponse<byte[]> list = call("GET", "/admin/feeds", admin());
        assertThat(list.statusCode()).isEqualTo(200);
        assertThat(body(list)).contains("\"cityName\":\"Testville\"").doesNotContain("localPath");

        HttpResponse<byte[]> one = call("GET", "/admin/feeds/1", admin());
        assertThat(one.statusCode()).isEqualTo(200);
        assertThat(body(one)).contains("\"id\":1");

        HttpResponse<byte[]> expires = call("GET", "/admin/feeds/1/expires", admin());
        assertThat(expires.statusCode()).isEqualTo(200);
        assertThat(body(expires)).isEqualTo("\"2027-12-09\"");
    }

    @Test
    @SuppressWarnings("unchecked")
    void authenticatedPostsWorkWithoutACsrfToken() throws Exception {
        doAnswer(inv -> {
            Consumer<String> onResult = inv.getArgument(0);
            onResult.accept("Testville is up to date!");
            return null;
        }).when(feedUpdateJob).updateFeeds(any(Consumer.class));

        HttpResponse<byte[]> update = call("POST", "/admin/feeds/update", admin());
        assertThat(update.statusCode()).isEqualTo(200);
        assertThat(update.headers().firstValue("Content-Type")).hasValueSatisfying(v -> assertThat(v).startsWith("text/plain"));
        assertThat(body(update)).isEqualTo("Testville is up to date!\n");
        verify(feedUpdateJob, times(1)).updateFeeds(any(Consumer.class));

        HttpResponse<byte[]> create = call("POST", "/admin/feeds", admin());
        assertThat(create.statusCode()).isEqualTo(200);
        assertThat(body(create)).contains("\"cityName\":\"SecProbe\"").contains("\"status\":\"new\"");
        verify(repo, times(1)).save(any(Feed.class));

        HttpResponse<byte[]> download = call("POST", "/admin/feeds/1/download", admin());
        assertThat(download.statusCode()).isEqualTo(200);
        verify(feedService, times(1)).download(1L);
    }

    @Test
    void badGatewayFromDownloadStays502AsProblemJsonForTheAdmin() throws Exception {
        when(feedService.download(2L)).thenThrow(new ResponseStatusException(HttpStatus.BAD_GATEWAY, "source returned 403"));

        HttpResponse<byte[]> r = call("POST", "/admin/feeds/2/download", admin());

        assertThat(r.statusCode()).isEqualTo(502);
        assertProblem(r, 502, "Bad Gateway", "/admin/feeds/2/download");
        assertThat(body(r)).contains("\"detail\":\"source returned 403\"");
    }

    /** application/problem+json with the RFC 9457 fields; Boot's error-JSON "path"/"timestamp" must not appear. */
    private static void assertProblem(HttpResponse<byte[]> r, int status, String title, String instance) {
        assertThat(r.statusCode()).isEqualTo(status);
        assertThat(r.headers().firstValue("Content-Type")).hasValue("application/problem+json");
        Map<String, Object> json = com.jayway.jsonpath.JsonPath.read(body(r), "$");
        assertThat(json).containsEntry("status", status).containsEntry("title", title).containsEntry("instance", instance)
                .doesNotContainKeys("path", "timestamp", "error");
    }

    // ---- problem+json through the real filter chain (authenticated) ----

    @Test
    void malformedJsonIs400ProblemJson() throws Exception {
        HttpResponse<byte[]> r = send("POST", "/admin/feeds", admin(), "application/json", "{\"cityName\": ");
        assertProblem(r, 400, "Bad Request", "/admin/feeds");
        assertThat(body(r)).contains("\"detail\":\"Failed to read request\"");
        verify(repo, never()).save(any());
    }

    @Test
    void wrongMethodIs405ProblemJsonWithAllowHeader() throws Exception {
        HttpResponse<byte[]> r = send("DELETE", "/admin/feeds", admin(), null, null);
        assertProblem(r, 405, "Method Not Allowed", "/admin/feeds");
        assertThat(r.headers().firstValue("Allow")).hasValueSatisfying(v -> assertThat(v.split(",\\s*")).containsExactlyInAnyOrder("GET", "POST"));
        assertThat(body(r)).contains("\"detail\":\"Method 'DELETE' is not supported.\"");
    }

    @Test
    void wrongContentTypeIs415ProblemJson() throws Exception {
        HttpResponse<byte[]> r = send("POST", "/admin/feeds", admin(), "text/plain", "cityName=x");
        assertProblem(r, 415, "Unsupported Media Type", "/admin/feeds");
        assertThat(body(r)).contains("\"detail\":\"Content-Type 'text/plain").contains("is not supported.\"");
        verify(repo, never()).save(any());
    }

    @Test
    void nonNumericIdIs400ProblemJson() throws Exception {
        HttpResponse<byte[]> r = send("GET", "/admin/feeds/abc", admin(), null, null);
        assertProblem(r, 400, "Bad Request", "/admin/feeds/abc");
        assertThat(body(r)).contains("\"detail\":\"Failed to convert 'id' with value: 'abc'\"");
        verify(repo, never()).findById(anyLong());

        // same on the public side, anonymously
        assertProblem(send("GET", "/api/feeds/abc/file", null, null, null), 400, "Bad Request", "/api/feeds/abc/file");
    }

    @Test
    void unknownIdIsProblemDetail404NotAnAuthError() throws Exception {
        HttpResponse<byte[]> admin404 = call("GET", "/admin/feeds/999999", admin());
        assertThat(admin404.statusCode()).isEqualTo(404);
        assertThat(admin404.headers().firstValue("Content-Type")).hasValue("application/problem+json");
        assertThat(body(admin404)).contains("\"detail\":\"Feed not found\"");
        // the NoSuchElementException handler is unchanged: exactly detail/instance/status/title
        assertProblem(admin404, 404, "Not Found", "/admin/feeds/999999");
        Map<String, Object> json = com.jayway.jsonpath.JsonPath.read(body(admin404), "$");
        assertThat(json).containsOnlyKeys("title", "status", "detail", "instance"); // type=about:blank is omitted

        HttpResponse<byte[]> public404 = call("GET", "/api/feeds/999999/file", null);
        assertThat(public404.statusCode()).isEqualTo(404);
        assertThat(public404.headers().firstValue("Content-Type")).hasValue("application/problem+json");
        assertThat(public404.headers().firstValue("WWW-Authenticate")).isEmpty();
    }

    // ---- /api/** ----

    @Test
    void publicRoutesAreOpenWithoutCredentials() throws Exception {
        Files.createDirectories(FeedService.FEEDS_ROOT);
        servedFile = FeedService.FEEDS_ROOT.resolve("security-test-" + UUID.randomUUID() + ".zip");
        byte[] bytes = "PK-security-test".getBytes(StandardCharsets.UTF_8);
        Files.write(servedFile, bytes);
        when(repo.findById(3L)).thenReturn(Optional.of(feed(3L, servedFile.toString())));

        HttpResponse<byte[]> list = call("GET", "/api/feeds", null);
        assertThat(list.statusCode()).isEqualTo(200);
        assertThat(body(list)).isEqualTo("[{\"id\":1,\"cityName\":\"Testville\",\"companyName\":\"TestCo\"}]");
        ArgumentCaptor<Sort> sort = ArgumentCaptor.forClass(Sort.class);
        verify(repo).findAll(sort.capture());
        assertThat(sort.getValue()).isEqualTo(Sort.by("id"));
        verify(repo, never()).findAll();

        HttpResponse<byte[]> file = call("GET", "/api/feeds/3/file", null);
        assertThat(file.statusCode()).isEqualTo(200);
        assertThat(file.body()).isEqualTo(bytes);
        assertThat(file.headers().firstValue("WWW-Authenticate")).isEmpty();

        // correct admin credentials on a public route are fine too
        assertThat(call("GET", "/api/feeds", admin()).statusCode()).isEqualTo(200);
    }

    @Test
    void badBasicCredentialsOnAPublicRouteAre401() throws Exception {
        // BasicAuthenticationFilter rejects a bad Authorization header before authorization runs, even under permitAll
        HttpResponse<byte[]> r = call("GET", "/api/feeds", basic(adminUser, "wrong-" + adminPassword));
        assertThat(r.statusCode()).isEqualTo(401);
        assertThat(r.headers().firstValue("WWW-Authenticate")).hasValueSatisfying(v -> assertThat(v).startsWith("Basic realm="));
        verify(repo, never()).findAll();
        verify(repo, never()).findAll(any(Sort.class));
    }

    @Test
    void errorDispatchFromAPublicRouteIsPermittedSoTheRealStatusComesThrough() throws Exception {
        // localPath null -> ResponseStatusException(404): since GlobalExceptionHandler extends ResponseEntityExceptionHandler
        // the advice renders it as problem+json directly (no ERROR dispatch any more)
        when(repo.findById(4L)).thenReturn(Optional.of(feed(4L, null)));

        HttpResponse<byte[]> missingFile = call("GET", "/api/feeds/4/file", null);
        assertProblem(missingFile, 404, "Not Found", "/api/feeds/4/file");

        // no handler: NoResourceFoundException, also handled by the advice
        HttpResponse<byte[]> noRoute = call("GET", "/api/does-not-exist", null);
        assertProblem(noRoute, 404, "Not Found", "/api/does-not-exist");

        // an exception no handler knows still goes through Boot's ERROR dispatch to /error, which must be permitted
        // (otherwise the anonymous caller would see 401 instead of the real 500)
        when(repo.findById(5L)).thenThrow(new IllegalStateException("database down"));
        HttpResponse<byte[]> unhandled = call("GET", "/api/feeds/5/file", null);
        assertThat(unhandled.statusCode()).isEqualTo(500);
        assertThat(unhandled.headers().firstValue("WWW-Authenticate")).isEmpty();
        assertThat(body(unhandled)).contains("\"status\":500").contains("\"path\":\"/api/feeds/5/file\"")
                .doesNotContain("database down");
    }

    // ---- everything else ----

    @ParameterizedTest(name = "{0} {1}")
    @CsvSource({"GET, /foo", "GET, /", "GET, /actuator/health", "GET, /index.html", "POST, /foo", "GET, /feeds"})
    void unlistedPathsAreDenied401AnonymousAnd403ForTheAdmin(String method, String path) throws Exception {
        HttpResponse<byte[]> anonymous = call(method, path, null);
        assertThat(anonymous.statusCode()).isEqualTo(401);
        assertThat(anonymous.headers().firstValue("WWW-Authenticate")).isPresent();

        HttpResponse<byte[]> asAdmin = call(method, path, admin());
        assertThat(asAdmin.statusCode()).isEqualTo(403);
        verifyNoInteractions(feedService, feedUpdateJob);
    }

    @Test
    void noSessionIsKeptAfterASuccessfulLogin() throws Exception {
        HttpResponse<byte[]> ok = call("GET", "/admin/feeds", admin());
        assertThat(ok.statusCode()).isEqualTo(200);
        assertThat(ok.headers().allValues("Set-Cookie")).isEmpty();

        // even if a client replays whatever it got, nothing authenticates it except the Authorization header
        HttpResponse<byte[]> again = call("GET", "/admin/feeds", null);
        assertThat(again.statusCode()).isEqualTo(401);

        HttpRequest withFakeSession = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/admin/feeds"))
                .header("Cookie", "JSESSIONID=0123456789ABCDEF").GET().build();
        HttpResponse<String> fake = http.send(withFakeSession, HttpResponse.BodyHandlers.ofString());
        assertThat(fake.statusCode()).isEqualTo(401);
        assertThat(fake.headers().allValues("Set-Cookie")).isEmpty();
    }
}
