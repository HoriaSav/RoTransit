package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.repository.FeedRepository;
import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManagerFactory;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ProxySelector;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * FeedService.download without the internet.
 * <p>
 * The source URL is hard-coded to https://files.mobilitydatabase.org/..., and FeedService builds its own HttpClient,
 * so there is no injection seam. The JDK HttpClient picks up the JVM-wide default ProxySelector and default SSLContext
 * when it is built, so this test installs (and afterwards restores) a local CONNECT proxy that tunnels every request
 * to a local HTTPS server whose throwaway self-signed certificate (generated with keytool at test time) is for
 * files.mobilitydatabase.org. No product code is touched and no real network traffic happens.
 * <p>
 * FEEDS_ROOT is the relative path "feeds", so the test uses ids 990001..990009 inside ./feeds and deletes them afterwards.
 */
class FeedServiceDownloadTest {

    private static final String HOST = "files.mobilitydatabase.org";
    /** A small but real zip: download() now rejects bodies that are not a readable zip. */
    private static final byte[] ZIP_BYTES = zip("stops.txt", "stop_id,stop_name\n1,FeedServiceDownloadTest\n");
    private static final List<Long> IDS = List.of(990001L, 990002L, 990003L, 990004L, 990005L, 990006L, 990007L, 990008L, 990009L, 990010L, 990011L, 990012L, 990013L, 990014L);
    /** A real zip: feed_info.txt feed_end_date 2028-05-31 wins over calendar.txt end_date 2029-12-31. */
    private static final byte[] DATED_ZIP = zip(
            "feed_info.txt", "feed_publisher_name,feed_publisher_url,feed_lang,feed_end_date\nP,https://x,ro,20280531\n",
            "calendar.txt", "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n"
                    + "wk,1,1,1,1,1,0,0,20260101,20291231\n");
    /** A real zip without feed_info.txt, calendar.txt or calendar_dates.txt. */
    private static final byte[] NO_DATES_ZIP = zip("stops.txt", "stop_id,stop_name\n1,A\n");
    /** A 200 body that is not a zip at all (e.g. an HTML error page). */
    private static final byte[] HTML_BODY = "<html>not a zip</html>".getBytes(StandardCharsets.UTF_8);
    /** Starts with a valid local file header (PK\\3\\4) but is cut before the central directory. */
    private static final byte[] TRUNCATED_ZIP = java.util.Arrays.copyOf(DATED_ZIP, DATED_ZIP.length / 2);

    private static HttpsServer https;
    private static ServerSocket proxy;
    private static Thread proxyThread;
    private static ProxySelector previousProxySelector;
    private static SSLContext previousSslContext;
    private static final List<String> connectTargets = new CopyOnWriteArrayList<>();
    private static final List<String> requestedPaths = new CopyOnWriteArrayList<>();

    private final FeedRepository repo = mock(FeedRepository.class);
    private FeedService service;

    @BeforeAll
    static void startFakeSource(@TempDir Path tmp) throws Exception {
        Path keystore = tmp.resolve("fake-source.p12");
        Process keytool = new ProcessBuilder(
                Path.of(System.getProperty("java.home"), "bin", "keytool").toString(),
                "-genkeypair", "-alias", "fake", "-keyalg", "RSA", "-keysize", "2048", "-validity", "2",
                "-dname", "CN=" + HOST, "-ext", "SAN=dns:" + HOST,
                "-keystore", keystore.toString(), "-storetype", "PKCS12",
                "-storepass", "changeit", "-keypass", "changeit")
                .redirectErrorStream(true).start();
        String keytoolOutput = new String(keytool.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        assertThat(keytool.waitFor(60, TimeUnit.SECONDS)).isTrue();
        assertThat(keytool.exitValue()).as(keytoolOutput).isZero();

        char[] pass = "changeit".toCharArray();
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (InputStream in = Files.newInputStream(keystore)) {
            ks.load(in, pass);
        }
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(ks, pass);
        SSLContext serverCtx = SSLContext.getInstance("TLS");
        serverCtx.init(kmf.getKeyManagers(), null, null);

        KeyStore trust = KeyStore.getInstance("PKCS12");
        trust.load(null, null);
        trust.setCertificateEntry("fake", ks.getCertificate("fake"));
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(trust);
        SSLContext clientCtx = SSLContext.getInstance("TLS");
        clientCtx.init(null, tmf.getTrustManagers(), null);

        https = HttpsServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        https.setHttpsConfigurator(new HttpsConfigurator(serverCtx));
        https.createContext("/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            requestedPaths.add(path);
            exchange.getRequestBody().readAllBytes();
            switch (path) {
                case "/mdb-ok/latest.zip" -> {
                    exchange.sendResponseHeaders(200, ZIP_BYTES.length);
                    try (OutputStream out = exchange.getResponseBody()) {
                        out.write(ZIP_BYTES);
                    }
                }
                case "/mdb-dated/latest.zip" -> {
                    exchange.sendResponseHeaders(200, DATED_ZIP.length);
                    try (OutputStream out = exchange.getResponseBody()) {
                        out.write(DATED_ZIP);
                    }
                }
                case "/mdb-nodates/latest.zip" -> {
                    exchange.sendResponseHeaders(200, NO_DATES_ZIP.length);
                    try (OutputStream out = exchange.getResponseBody()) {
                        out.write(NO_DATES_ZIP);
                    }
                }
                case "/mdb-html/latest.zip" -> {
                    exchange.sendResponseHeaders(200, HTML_BODY.length);
                    try (OutputStream out = exchange.getResponseBody()) {
                        out.write(HTML_BODY);
                    }
                }
                case "/mdb-truncated/latest.zip" -> {
                    exchange.sendResponseHeaders(200, TRUNCATED_ZIP.length);
                    try (OutputStream out = exchange.getResponseBody()) {
                        out.write(TRUNCATED_ZIP);
                    }
                }
                case "/mdb-drop/latest.zip" -> {
                    // promise 100000 bytes, send 1000, then fail the handler: the server closes the connection mid-body
                    exchange.sendResponseHeaders(200, 100_000);
                    OutputStream out = exchange.getResponseBody();
                    out.write(java.util.Arrays.copyOf(DATED_ZIP, 1000));
                    out.flush();
                    throw new IOException("fake server drops the connection mid-body");
                }
                case "/mdb-redirect/latest.zip" -> {
                    exchange.getResponseHeaders().add("Location", "https://" + HOST + "/mdb-ok/latest.zip");
                    exchange.sendResponseHeaders(302, -1);
                    exchange.close();
                }
                default -> {
                    byte[] body = "<Error>AccessDenied</Error>".getBytes(StandardCharsets.UTF_8);
                    exchange.sendResponseHeaders(403, body.length);
                    try (OutputStream out = exchange.getResponseBody()) {
                        out.write(body);
                    }
                }
            }
        });
        https.start();

        proxy = new ServerSocket(0, 50, InetAddress.getLoopbackAddress());
        proxyThread = new Thread(FeedServiceDownloadTest::acceptLoop, "fake-connect-proxy");
        proxyThread.setDaemon(true);
        proxyThread.start();

        previousProxySelector = ProxySelector.getDefault();
        previousSslContext = SSLContext.getDefault();
        ProxySelector.setDefault(ProxySelector.of(new InetSocketAddress(InetAddress.getLoopbackAddress(), proxy.getLocalPort())));
        SSLContext.setDefault(clientCtx);
    }

    @AfterAll
    static void stopFakeSource() throws IOException {
        ProxySelector.setDefault(previousProxySelector);
        SSLContext.setDefault(previousSslContext);
        if (proxy != null) {
            proxy.close();
        }
        if (https != null) {
            https.stop(0);
        }
    }

    @BeforeEach
    void setUp() throws IOException {
        cleanFeedsDir();
        connectTargets.clear();
        requestedPaths.clear();
        // FeedService builds its HttpClient at construction, after the defaults above are installed
        service = new FeedService(repo);
        when(repo.save(any(Feed.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    @AfterEach
    void tearDown() throws IOException {
        Thread.interrupted(); // guard: never leak an interrupt flag into the next test
        cleanFeedsDir();
    }

    /** Runs download() and returns {thrown, interrupt flag right after the call}; the flag is always cleared. */
    private Object[] downloadAndTakeInterruptFlag(long id) {
        Throwable thrown;
        boolean flag;
        try {
            thrown = catchThrowable(() -> service.download(id));
        } finally {
            flag = Thread.interrupted();
        }
        return new Object[] {thrown, flag};
    }

    private Feed feed(long id, String sourceId) {
        Feed feed = new Feed();
        ReflectionTestUtils.setField(feed, "id", id);
        feed.setCityName("Testville");
        feed.setCompanyName("TestCo");
        feed.setSourceId(sourceId);
        feed.setStatus("new");
        when(repo.findById(id)).thenReturn(Optional.of(feed));
        return feed;
    }

    @Test
    void okResponseIsMovedToFeedsIdZipAndFeedIsUpdated() throws Exception {
        feed(990001L, "mdb-ok");

        Feed result = service.download(990001L);

        Path target = FeedService.FEEDS_ROOT.resolve("990001.zip");
        assertThat(Files.readAllBytes(target)).isEqualTo(ZIP_BYTES);
        assertThat(partFiles(990001L)).isEmpty();
        assertThat(result.getLocalPath()).isEqualTo(target.toString());
        assertThat(result.getStatus()).isEqualTo("downloaded");
        assertThat(result.getSourceUrl()).isEqualTo("https://" + HOST + "/mdb-ok/latest.zip");
        assertThat(result.getDownloadedAt()).isNotNull();
        assertThat(connectTargets).containsExactly(HOST + ":443");
        assertThat(requestedPaths).containsExactly("/mdb-ok/latest.zip");
        verify(repo).save(result);
    }

    @Test
    void non200SourceGives502MarksTheFeedFailedAndLeavesNoTargetAndNoTempFile() throws Exception {
        Feed feed = feed(990002L, "mdb-does-not-exist-xyz");

        assertThatThrownBy(() -> service.download(990002L))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(e -> assertThat(((ResponseStatusException) e).getStatusCode().value()).isEqualTo(502));

        assertThat(FeedService.FEEDS_ROOT.resolve("990002.zip")).doesNotExist();
        assertThat(partFiles(990002L)).isEmpty();
        assertThat(feed.getStatus()).isEqualTo("failed");
        assertThat(feed.getLocalPath()).isNull();
        Feed saved = savedOnce();
        assertThat(saved).isSameAs(feed); // the instance loaded by download() itself, not a fresh copy
        assertThat(saved.getStatus()).isEqualTo("failed");
        assertThat(saved.getLocalPath()).isNull();
        assertThat(saved.getSourceUrl()).isNull();
        assertThat(saved.getDownloadedAt()).isNull();
        assertThat(saved.getExpiresOn()).isNull();
    }

    /** Exactly one save, returning the entity that was passed to it. */
    private Feed savedOnce() {
        ArgumentCaptor<Feed> captor = ArgumentCaptor.forClass(Feed.class);
        verify(repo, times(1)).save(captor.capture());
        return captor.getValue();
    }

    @Test
    void non200SourceDoesNotTouchAnExistingZip() throws Exception {
        feed(990004L, "mdb-does-not-exist-xyz");
        Files.createDirectories(FeedService.FEEDS_ROOT);
        Path existing = FeedService.FEEDS_ROOT.resolve("990004.zip");
        Files.writeString(existing, "previous good feed");

        assertThatThrownBy(() -> service.download(990004L)).isInstanceOf(ResponseStatusException.class);

        assertThat(existing).hasContent("previous good feed");
        assertThat(partFiles(990004L)).isEmpty();
    }

    @Test
    void redirectIsFollowed() throws Exception {
        feed(990003L, "mdb-redirect");

        Feed result = service.download(990003L);

        assertThat(Files.readAllBytes(FeedService.FEEDS_ROOT.resolve("990003.zip"))).isEqualTo(ZIP_BYTES);
        assertThat(partFiles(990003L)).isEmpty();
        assertThat(requestedPaths).containsExactly("/mdb-redirect/latest.zip", "/mdb-ok/latest.zip");
        assertThat(result.getStatus()).isEqualTo("downloaded");
        // sourceUrl records the configured URL, not the redirect target
        assertThat(result.getSourceUrl()).isEqualTo("https://" + HOST + "/mdb-redirect/latest.zip");
    }

    @Test
    void realZipSetsExpiresOnFromTheNewFileAndStatusDownloaded() throws Exception {
        feed(990005L, "mdb-dated");

        Feed result = service.download(990005L);

        assertThat(Files.readAllBytes(FeedService.FEEDS_ROOT.resolve("990005.zip"))).isEqualTo(DATED_ZIP);
        assertThat(result.getStatus()).isEqualTo("downloaded");
        assertThat(result.getExpiresOn()).isEqualTo(java.time.LocalDate.of(2028, 5, 31));
        assertThat(partFiles(990005L)).isEmpty();
        verify(repo).save(result);
    }

    @Test
    void zipWithoutDateSourcesStillSucceedsWithNullExpiresOn() throws Exception {
        Feed feed = feed(990006L, "mdb-nodates");
        feed.setExpiresOn(java.time.LocalDate.of(2020, 1, 1)); // stale value must not survive

        Feed result = service.download(990006L);

        assertThat(FeedService.FEEDS_ROOT.resolve("990006.zip")).exists();
        assertThat(result.getStatus()).isEqualTo("downloaded");
        assertThat(result.getExpiresOn()).isNull();
        assertThat(result.getDownloadedAt()).isNotNull();
        verify(repo).save(result);
    }

    @Test
    void previouslyFailedFeedIsResetToDownloadedWithExpiresOn() throws Exception {
        Feed feed = feed(990007L, "mdb-dated");
        feed.setStatus("failed");
        feed.setExpiresOn(null);

        Feed result = service.download(990007L);

        assertThat(result.getStatus()).isEqualTo("downloaded");
        assertThat(result.getExpiresOn()).isEqualTo(java.time.LocalDate.of(2028, 5, 31));
        assertThat(result.getLocalPath()).isEqualTo(FeedService.FEEDS_ROOT.resolve("990007.zip").toString());
    }

    @Test
    void nonZipBodyWith200Gives502MarksFailedAndKeepsTheExistingZipAndOtherFields() throws Exception {
        assertCorruptBodyIsRejected(990008L, "mdb-html");
    }

    @Test
    void truncatedZipWith200Gives502MarksFailedAndKeepsTheExistingZipAndOtherFields() throws Exception {
        assertThat(TRUNCATED_ZIP).startsWith((byte) 'P', (byte) 'K', (byte) 3, (byte) 4);
        assertCorruptBodyIsRejected(990009L, "mdb-truncated");
    }

    private void assertCorruptBodyIsRejected(long id, String sourceId) throws Exception {
        Feed feed = feed(id, sourceId);
        Files.createDirectories(FeedService.FEEDS_ROOT);
        Path existing = FeedService.FEEDS_ROOT.resolve(id + ".zip");
        Files.write(existing, DATED_ZIP);
        java.time.Instant downloadedAt = java.time.Instant.parse("2026-01-02T03:04:05Z");
        feed.setStatus("downloaded");
        feed.setLocalPath(existing.toString());
        feed.setSourceUrl("https://example.invalid/previous.zip");
        feed.setDownloadedAt(downloadedAt);
        feed.setExpiresOn(java.time.LocalDate.of(2028, 5, 31));

        assertThatThrownBy(() -> service.download(id))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(e -> {
                    ResponseStatusException rse = (ResponseStatusException) e;
                    assertThat(rse.getStatusCode().value()).isEqualTo(502);
                    assertThat(rse.getCause()).isInstanceOf(java.util.zip.ZipException.class);
                    assertThat(rse.getReason())
                            .contains("invalid zip")
                            .contains("https://" + HOST + "/" + sourceId + "/latest.zip");
                });

        assertThat(requestedPaths).containsExactly("/" + sourceId + "/latest.zip");
        assertFailedButOtherwiseUntouched(feed, existing, downloadedAt);
    }

    /** status flips to failed and is saved once; the previous zip and every other field stay as they were. */
    private void assertFailedButOtherwiseUntouched(Feed feed, Path existing, java.time.Instant downloadedAt) throws IOException {
        assertThat(Files.readAllBytes(existing)).isEqualTo(DATED_ZIP);
        assertThat(partFiles(feed.getId())).isEmpty();
        assertThat(feed.getStatus()).isEqualTo("failed");
        assertThat(feed.getLocalPath()).isEqualTo(existing.toString());
        assertThat(feed.getSourceUrl()).isEqualTo("https://example.invalid/previous.zip");
        assertThat(feed.getDownloadedAt()).isEqualTo(downloadedAt);
        assertThat(feed.getExpiresOn()).isEqualTo(java.time.LocalDate.of(2028, 5, 31));
        Feed saved = savedOnce();
        assertThat(saved).isSameAs(feed);
        assertThat(saved.getStatus()).isEqualTo("failed");
        assertThat(saved.getLocalPath()).isEqualTo(existing.toString());
        assertThat(saved.getSourceUrl()).isEqualTo("https://example.invalid/previous.zip");
        assertThat(saved.getDownloadedAt()).isEqualTo(downloadedAt);
        assertThat(saved.getExpiresOn()).isEqualTo(java.time.LocalDate.of(2028, 5, 31));
    }

    /** A previously good feed: existing zip on disk plus the fields a successful download leaves behind. */
    private Feed previouslyDownloaded(long id, String sourceId, java.time.Instant downloadedAt) throws IOException {
        Feed feed = feed(id, sourceId);
        Files.createDirectories(FeedService.FEEDS_ROOT);
        Path existing = FeedService.FEEDS_ROOT.resolve(id + ".zip");
        Files.write(existing, DATED_ZIP);
        feed.setStatus("downloaded");
        feed.setLocalPath(existing.toString());
        feed.setSourceUrl("https://example.invalid/previous.zip");
        feed.setDownloadedAt(downloadedAt);
        feed.setExpiresOn(java.time.LocalDate.of(2028, 5, 31));
        return feed;
    }

    @Test
    void connectionDroppedMidBodyMarksFailedSavesOnceAndRethrowsTheIOExceptionUnwrapped() throws Exception {
        java.time.Instant downloadedAt = java.time.Instant.parse("2026-01-02T03:04:05Z");
        Feed feed = previouslyDownloaded(990010L, "mdb-drop", downloadedAt);

        Object[] r = downloadAndTakeInterruptFlag(990010L);
        Throwable thrown = (Throwable) r[0];

        assertThat((boolean) r[1]).as("an IOException must not set the interrupt flag").isFalse();
        assertThat(thrown).isInstanceOf(IOException.class).isNotInstanceOf(ResponseStatusException.class);
        assertThat(requestedPaths).containsExactly("/mdb-drop/latest.zip");
        assertFailedButOtherwiseUntouched(feed, Path.of(feed.getLocalPath()), downloadedAt);
    }

    @Test
    void ioExceptionFromTheHttpClientIsRethrownAsTheSameInstanceAndLeavesNoInterruptFlag() throws Exception {
        java.time.Instant downloadedAt = java.time.Instant.parse("2026-01-02T03:04:05Z");
        Feed feed = previouslyDownloaded(990011L, "mdb-ok", downloadedAt);
        HttpClient client = mock(HttpClient.class);
        IOException boom = new IOException("connection reset");
        when(client.send(any(), any())).thenThrow(boom);
        ReflectionTestUtils.setField(service, "client", client);

        Object[] r = downloadAndTakeInterruptFlag(990011L);
        Throwable thrown = (Throwable) r[0];

        assertThat((boolean) r[1]).as("an IOException must not set the interrupt flag").isFalse();
        assertThat(thrown).isSameAs(boom);
        assertThat(requestedPaths).isEmpty();
        assertFailedButOtherwiseUntouched(feed, Path.of(feed.getLocalPath()), downloadedAt);
    }

    @Test
    void interruptedExceptionFromTheHttpClientMarksFailedRethrowsTheSameInstanceAndRestoresTheFlag() throws Exception {
        java.time.Instant downloadedAt = java.time.Instant.parse("2026-01-02T03:04:05Z");
        Feed feed = previouslyDownloaded(990012L, "mdb-ok", downloadedAt);
        HttpClient client = mock(HttpClient.class);
        InterruptedException interrupted = new InterruptedException("stop");
        when(client.send(any(), any())).thenThrow(interrupted);
        ReflectionTestUtils.setField(service, "client", client);

        Object[] r = downloadAndTakeInterruptFlag(990012L);
        Throwable thrown = (Throwable) r[0];

        assertThat((boolean) r[1]).as("interrupt flag restored after the throw").isTrue();
        assertThat(thrown).isSameAs(interrupted);
        assertFailedButOtherwiseUntouched(feed, Path.of(feed.getLocalPath()), downloadedAt);
    }

    @Test
    void realInterruptDuringSendMarksFailedRethrowsAndRestoresTheFlag() throws Exception {
        java.time.Instant downloadedAt = java.time.Instant.parse("2026-01-02T03:04:05Z");
        Feed feed = previouslyDownloaded(990013L, "mdb-ok", downloadedAt);

        Thread.currentThread().interrupt();
        Object[] r = downloadAndTakeInterruptFlag(990013L);
        Throwable thrown = (Throwable) r[0];

        System.out.println("[r19] interrupt flag after download(): " + r[1] + ", thrown: " + thrown);
        assertThat((boolean) r[1]).as("interrupt flag restored after the throw").isTrue();
        assertThat(thrown).isInstanceOf(InterruptedException.class);
        assertFailedButOtherwiseUntouched(feed, Path.of(feed.getLocalPath()), downloadedAt);
    }

    @Test
    void failedSaveRunsWithTheFlagClearAndTheFlagIsRestoredOnlyAfterIt() throws Exception {
        java.time.Instant downloadedAt = java.time.Instant.parse("2026-01-02T03:04:05Z");
        Feed feed = previouslyDownloaded(990014L, "mdb-ok", downloadedAt);
        HttpClient client = mock(HttpClient.class);
        InterruptedException interrupted = new InterruptedException("stop");
        when(client.send(any(), any())).thenThrow(interrupted);
        ReflectionTestUtils.setField(service, "client", client);
        List<Boolean> flagDuringSave = new CopyOnWriteArrayList<>();
        when(repo.save(any(Feed.class))).thenAnswer(inv -> {
            flagDuringSave.add(Thread.currentThread().isInterrupted());
            return inv.getArgument(0);
        });

        Object[] r = downloadAndTakeInterruptFlag(990014L);

        // the save talks to the database, so it must not run with the flag set (a set flag can abort a blocking pool wait)
        assertThat(flagDuringSave).containsExactly(false);
        assertThat((boolean) r[1]).isTrue();
        assertThat(r[0]).isSameAs(interrupted);
        assertFailedButOtherwiseUntouched(feed, Path.of(feed.getLocalPath()), downloadedAt);
    }

    private static byte[] zip(String... nameContentPairs) {
        try {
            java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
            try (java.util.zip.ZipOutputStream out = new java.util.zip.ZipOutputStream(bytes)) {
                for (int i = 0; i < nameContentPairs.length; i += 2) {
                    out.putNextEntry(new java.util.zip.ZipEntry(nameContentPairs[i]));
                    out.write(nameContentPairs[i + 1].getBytes(StandardCharsets.UTF_8));
                    out.closeEntry();
                }
            }
            return bytes.toByteArray();
        } catch (IOException e) {
            throw new java.io.UncheckedIOException(e);
        }
    }

    private static List<Path> partFiles(long id) throws IOException {
        if (!Files.isDirectory(FeedService.FEEDS_ROOT)) {
            return List.of();
        }
        try (Stream<Path> files = Files.list(FeedService.FEEDS_ROOT)) {
            return files.filter(p -> {
                String name = p.getFileName().toString();
                return name.startsWith(id + "-") && name.endsWith(".part");
            }).toList();
        }
    }

    private static void cleanFeedsDir() throws IOException {
        for (long id : IDS) {
            Files.deleteIfExists(FeedService.FEEDS_ROOT.resolve(id + ".zip"));
            for (Path part : partFiles(id)) {
                Files.deleteIfExists(part);
            }
        }
    }

    // ---- minimal CONNECT proxy that tunnels everything to the local HTTPS server ----

    private static void acceptLoop() {
        while (!proxy.isClosed()) {
            try {
                Socket client = proxy.accept();
                Thread t = new Thread(() -> tunnel(client), "fake-connect-tunnel");
                t.setDaemon(true);
                t.start();
            } catch (IOException e) {
                return;
            }
        }
    }

    private static void tunnel(Socket client) {
        try (client; Socket upstream = new Socket(InetAddress.getLoopbackAddress(), https.getAddress().getPort())) {
            InputStream in = client.getInputStream();
            String head = readHead(in);
            String requestLine = head.lines().findFirst().orElse("");
            if (!requestLine.startsWith("CONNECT ")) {
                client.getOutputStream().write("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1));
                return;
            }
            connectTargets.add(requestLine.split(" ")[1]);
            client.getOutputStream().write("HTTP/1.1 200 Connection established\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1));
            client.getOutputStream().flush();
            Thread up = new Thread(() -> pipe(in, upstream), "fake-connect-up");
            up.setDaemon(true);
            up.start();
            pipe(upstream.getInputStream(), client);
            up.join(5000);
        } catch (Exception ignored) {
            // connection torn down by either side
        }
    }

    private static String readHead(InputStream in) throws IOException {
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        int b;
        while ((b = in.read()) != -1) {
            buf.write(b);
            byte[] a = buf.toByteArray();
            int n = a.length;
            if (n >= 4 && a[n - 4] == '\r' && a[n - 3] == '\n' && a[n - 2] == '\r' && a[n - 1] == '\n') {
                break;
            }
        }
        return buf.toString(StandardCharsets.ISO_8859_1);
    }

    private static void pipe(InputStream from, Socket to) {
        try {
            from.transferTo(to.getOutputStream());
            to.shutdownOutput();
        } catch (IOException ignored) {
            // closed
        }
    }
}
