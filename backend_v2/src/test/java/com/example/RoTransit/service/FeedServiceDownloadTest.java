package com.example.RoTransit.service;

import com.example.RoTransit.TestEntities;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedSource;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.entity.Operator;
import com.example.RoTransit.repository.CityRepository;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedSourceRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import com.example.RoTransit.repository.OperatorRepository;
import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.dao.DataAccessResourceFailureException;
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
import java.nio.file.attribute.FileTime;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * FeedService.download without the internet.
 * <p>
 * The source URL is https://files.mobilitydatabase.org/..., and FeedService builds its own HttpClient,
 * so there is no injection seam. The JDK HttpClient picks up the JVM-wide default ProxySelector and default SSLContext
 * when it is built, so this test installs (and afterwards restores) a local CONNECT proxy that tunnels every request
 * to a local HTTPS server whose throwaway self-signed certificate (generated with keytool at test time) is for
 * files.mobilitydatabase.org. No product code is touched and no real network traffic happens.
 * <p>
 * The repositories are mocks, but FeedVersionService is the real one, so the tests see the real
 * "demote the current version, then save the new one" calls (the database side is in FeedVersionSwitchTest).
 * <p>
 * FEEDS_ROOT is the relative path "feeds", so the test uses ids 990001..990030 inside ./feeds (files and feeds/{id}/
 * folders) and deletes them afterwards.
 */
class FeedServiceDownloadTest {

    private static final String HOST = "files.mobilitydatabase.org";
    /** A small but real zip: download() rejects bodies that are not a readable zip. It has no agency.txt. */
    private static final byte[] ZIP_BYTES = zip("stops.txt", "stop_id,stop_name\n1,FeedServiceDownloadTest\n");
    private static final List<Long> IDS = java.util.stream.LongStream.rangeClosed(990001L, 990030L).boxed().toList();
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
    /**
     * agency.txt with a BOM, a quoted name containing a comma, an agency without agency_id/url and a row without
     * agency_name (skipped). feed_info.txt has a feed_start_date.
     */
    private static final byte[] AGENCY_ZIP = zip(
            "agency.txt", "\uFEFFagency_id,agency_name,agency_url,agency_timezone\n"
                    + "A1,\"Transport Urban, Sinaia\",https://sinaia.example,Europe/Bucharest\n"
                    + ",Second Operator,,Europe/Bucharest\n"
                    + "A3,,https://nameless.example,Europe/Bucharest\n",
            "feed_info.txt", "feed_publisher_name,feed_start_date,feed_end_date\nP,20261101,20270430\n");
    /** agency.txt whose second row opens a quote that is never closed: the whole file is skipped. */
    private static final byte[] BROKEN_AGENCY_ZIP = zip(
            "agency.txt", "agency_id,agency_name,agency_url\nA1,Good One,https://x\nA2,\"Broken,https://y\n",
            "calendar.txt", "service_id,start_date,end_date\nwk,20260101,20291231\n");

    private static HttpsServer https;
    private static ServerSocket proxy;
    private static Thread proxyThread;
    private static ProxySelector previousProxySelector;
    private static SSLContext previousSslContext;
    private static final List<String> connectTargets = new CopyOnWriteArrayList<>();
    private static final List<String> requestedPaths = new CopyOnWriteArrayList<>();

    private final FeedRepository feeds = mock(FeedRepository.class);
    private final CityRepository cities = mock(CityRepository.class);
    private final FeedSourceRepository sources = mock(FeedSourceRepository.class);
    private final FeedVersionRepository versions = mock(FeedVersionRepository.class);
    private final OperatorRepository operators = mock(OperatorRepository.class);
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
                case "/mdb-agency/latest.zip" -> {
                    exchange.sendResponseHeaders(200, AGENCY_ZIP.length);
                    try (OutputStream out = exchange.getResponseBody()) {
                        out.write(AGENCY_ZIP);
                    }
                }
                case "/mdb-badagency/latest.zip" -> {
                    exchange.sendResponseHeaders(200, BROKEN_AGENCY_ZIP.length);
                    try (OutputStream out = exchange.getResponseBody()) {
                        out.write(BROKEN_AGENCY_ZIP);
                    }
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
        service = new FeedService(feeds, cities, sources, versions, new FeedVersionService(versions, operators));
        when(versions.save(any(FeedVersion.class))).thenAnswer(inv -> inv.getArgument(0));
        when(operators.saveAll(anyList())).thenAnswer(inv -> inv.getArgument(0));
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

    /** A feed with a priority-1 mobilitydb source "sourceId", as the repositories would return it. */
    private FeedSource feed(long id, String sourceId) {
        Feed feed = TestEntities.feed(id, "Testville", "TestCo");
        FeedSource source = TestEntities.mobilityDbSource(feed, sourceId);
        when(feeds.findById(id)).thenReturn(Optional.of(feed));
        when(sources.findByFeedIdAndPriority(id, 1)).thenReturn(Optional.of(source));
        return source;
    }

    /** Exactly one version saved; returns it. */
    private FeedVersion savedOnce() {
        ArgumentCaptor<FeedVersion> captor = ArgumentCaptor.forClass(FeedVersion.class);
        verify(versions, times(1)).save(captor.capture());
        return captor.getValue();
    }

    /** The operators handed to saveAll (exactly one call). */
    @SuppressWarnings("unchecked")
    private List<Operator> savedOperators() {
        ArgumentCaptor<List<Operator>> captor = ArgumentCaptor.forClass(List.class);
        verify(operators, times(1)).saveAll(captor.capture());
        return captor.getValue();
    }

    private static String sha256(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }

    @Test
    void okResponseIsMovedToFeedsIdZipAndSavedAsTheCurrentVersion() throws Exception {
        FeedSource source = feed(990001L, "mdb-ok");

        FeedVersion result = service.download(990001L).version();

        Path target = fileOf(990001L, ZIP_BYTES); // feeds/990001/{sha256}.zip
        assertThat(Files.readAllBytes(target)).isEqualTo(ZIP_BYTES);
        assertThat(partFiles(990001L)).isEmpty();
        assertThat(result.getFeed()).isSameAs(source.getFeed());
        assertThat(result.getSource()).isSameAs(source);
        assertThat(result.getFilePath()).isEqualTo(target.toString());
        assertThat(result.getStatus()).isEqualTo(FeedVersion.CURRENT);
        assertThat(result.getSha256()).isEqualTo(sha256(ZIP_BYTES));
        assertThat(FeedService.FEEDS_ROOT.resolve("990001.zip")).as("no flat feeds/{id}.zip any more").doesNotExist();
        assertThat(result.getDownloadedAt()).isNotNull();
        assertThat(connectTargets).containsExactly(HOST + ":443");
        assertThat(requestedPaths).containsExactly("/mdb-ok/latest.zip");
        assertThat(savedOnce()).isSameAs(result);
        assertThat(savedOperators()).as("no agency.txt: no operators, and no error").isEmpty();
    }

    @Test
    void successDemotesThePreviousCurrentVersionBeforeSavingTheNewOne() throws Exception {
        feed(990007L, "mdb-dated");

        FeedVersion result = service.download(990007L).version();

        // demote first: the database allows only one 'current' row per feed
        InOrder order = inOrder(versions, operators);
        order.verify(versions).markCurrentAsOld(990007L);
        order.verify(versions).save(result);
        order.verify(operators).saveAll(anyList());
        assertThat(result.getStatus()).isEqualTo(FeedVersion.CURRENT);
    }

    @Test
    void non200SourceGives502StoresAFailedVersionAndLeavesNoTargetAndNoTempFile() throws Exception {
        FeedSource source = feed(990002L, "mdb-does-not-exist-xyz");

        assertThatThrownBy(() -> service.download(990002L))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(e -> assertThat(((ResponseStatusException) e).getStatusCode().value()).isEqualTo(502));

        assertThat(FeedService.FEEDS_ROOT.resolve("990002")).as("no per-feed folder either").doesNotExist();
        assertThat(partFiles(990002L)).isEmpty();
        FeedVersion saved = savedOnce();
        assertThat(saved.getStatus()).isEqualTo(FeedVersion.FAILED);
        assertThat(saved.getFeed()).isSameAs(source.getFeed());
        assertThat(saved.getSource()).isSameAs(source);
        assertThat(saved.getDownloadedAt()).as("time of the attempt").isNotNull();
        assertThat(saved.getFilePath()).isNull();
        assertThat(saved.getSha256()).isNull();
        assertThat(saved.getExpiresOn()).isNull();
        assertThat(saved.getStartsOn()).isNull();
        verify(versions, never()).markCurrentAsOld(anyLong());
        verify(operators, never()).saveAll(anyList());
    }

    @Test
    void feedWithoutAPriorityOneSourceStoresAFailedVersionWithoutAnyRequest() throws Exception {
        Feed feed = TestEntities.feed(990015L, "Testville", "TestCo");
        when(feeds.findById(990015L)).thenReturn(Optional.of(feed));
        when(sources.findByFeedIdAndPriority(990015L, 1)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.download(990015L))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("no source");

        assertThat(requestedPaths).isEmpty();
        FeedVersion saved = savedOnce();
        assertThat(saved.getStatus()).isEqualTo(FeedVersion.FAILED);
        assertThat(saved.getSource()).isNull();
        verify(versions, never()).markCurrentAsOld(anyLong());
    }

    @Test
    void non200SourceDoesNotTouchAnExistingZip() throws Exception {
        Path existing = previouslyDownloaded(990004L, "mdb-does-not-exist-xyz");

        assertThatThrownBy(() -> service.download(990004L)).isInstanceOf(ResponseStatusException.class);

        assertThat(existing).hasBinaryContent(DATED_ZIP);
        assertThat(filesIn(990004L)).containsExactly(existing);
        assertThat(partFiles(990004L)).isEmpty();
    }

    @Test
    void redirectIsFollowed() throws Exception {
        FeedSource source = feed(990003L, "mdb-redirect");

        FeedVersion result = service.download(990003L).version();

        assertThat(Files.readAllBytes(fileOf(990003L, ZIP_BYTES))).isEqualTo(ZIP_BYTES);
        assertThat(partFiles(990003L)).isEmpty();
        assertThat(requestedPaths).containsExactly("/mdb-redirect/latest.zip", "/mdb-ok/latest.zip");
        assertThat(result.getStatus()).isEqualTo(FeedVersion.CURRENT);
        // the version records the configured source (and so its URL), not the redirect target
        assertThat(result.getSource()).isSameAs(source);
        assertThat(result.getSource().downloadUrl()).isEqualTo("https://" + HOST + "/mdb-redirect/latest.zip");
    }

    @Test
    void realZipSetsExpiresOnAndStartsOnFromTheNewFile() throws Exception {
        feed(990005L, "mdb-dated");

        FeedVersion result = service.download(990005L).version();

        assertThat(Files.readAllBytes(fileOf(990005L, DATED_ZIP))).isEqualTo(DATED_ZIP);
        assertThat(result.getStatus()).isEqualTo(FeedVersion.CURRENT);
        assertThat(result.getExpiresOn()).isEqualTo(LocalDate.of(2028, 5, 31));
        // feed_info.txt has no feed_start_date here, so calendar.txt start_date is used
        assertThat(result.getStartsOn()).isEqualTo(LocalDate.of(2026, 1, 1));
        assertThat(partFiles(990005L)).isEmpty();
        assertThat(savedOnce()).isSameAs(result);
    }

    @Test
    void zipWithoutDateSourcesStillSucceedsWithNullDates() throws Exception {
        feed(990006L, "mdb-nodates");

        FeedVersion result = service.download(990006L).version();

        assertThat(fileOf(990006L, NO_DATES_ZIP)).exists();
        assertThat(result.getStatus()).isEqualTo(FeedVersion.CURRENT);
        assertThat(result.getExpiresOn()).isNull();
        assertThat(result.getStartsOn()).isNull();
        assertThat(result.getDownloadedAt()).isNotNull();
        assertThat(savedOnce()).isSameAs(result);
    }

    @Test
    void agencyTxtIsParsedIntoOperatorsOfTheNewVersion() throws Exception {
        feed(990016L, "mdb-agency");

        FeedVersion result = service.download(990016L).version();

        List<Operator> saved = savedOperators();
        assertThat(saved).extracting(Operator::getName)
                .containsExactly("Transport Urban, Sinaia", "Second Operator"); // the row without a name is skipped
        assertThat(saved).extracting(Operator::getAgencyId).containsExactly("A1", null);
        assertThat(saved).extracting(Operator::getUrl).containsExactly("https://sinaia.example", null);
        assertThat(saved).allSatisfy(o -> assertThat(o.getFeedVersion()).isSameAs(result));
        // feed_info.txt feed_start_date wins
        assertThat(result.getStartsOn()).isEqualTo(LocalDate.of(2026, 11, 1));
        assertThat(result.getExpiresOn()).isEqualTo(LocalDate.of(2027, 4, 30));
    }

    @Test
    void brokenAgencyTxtStillSucceedsWithNoOperators() throws Exception {
        feed(990017L, "mdb-badagency");

        FeedVersion result = service.download(990017L).version();

        assertThat(result.getStatus()).isEqualTo(FeedVersion.CURRENT);
        assertThat(result.getExpiresOn()).isEqualTo(LocalDate.of(2029, 12, 31));
        assertThat(fileOf(990017L, BROKEN_AGENCY_ZIP)).exists();
        // all or nothing: the good first row is dropped too, half a list would be misleading
        assertThat(savedOperators()).isEmpty();
    }

    @Test
    void nonZipBodyWith200Gives502StoresAFailedVersionAndKeepsTheExistingZip() throws Exception {
        assertCorruptBodyIsRejected(990008L, "mdb-html");
    }

    @Test
    void truncatedZipWith200Gives502StoresAFailedVersionAndKeepsTheExistingZip() throws Exception {
        assertThat(TRUNCATED_ZIP).startsWith((byte) 'P', (byte) 'K', (byte) 3, (byte) 4);
        assertCorruptBodyIsRejected(990009L, "mdb-truncated");
    }

    private void assertCorruptBodyIsRejected(long id, String sourceId) throws Exception {
        Path existing = previouslyDownloaded(id, sourceId);

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
        assertFailedAndCurrentUntouched(id, existing);
    }

    /**
     * One failed version is saved; the current version is never demoted (no markCurrentAsOld) and the previous zip
     * on disk is unchanged, so clients keep getting the last good file.
     */
    private void assertFailedAndCurrentUntouched(long id, Path existing) throws IOException {
        assertThat(Files.readAllBytes(existing)).isEqualTo(DATED_ZIP);
        assertThat(filesIn(id)).as("no new file next to the current one").containsExactly(existing);
        assertThat(partFiles(id)).isEmpty();
        assertThat(current.getStatus()).isEqualTo(FeedVersion.CURRENT);
        assertThat(current.getFilePath()).isEqualTo(existing.toString());
        FeedVersion saved = savedOnce();
        assertThat(saved.getStatus()).isEqualTo(FeedVersion.FAILED);
        assertThat(saved.getFeed().getId()).isEqualTo(id);
        assertThat(saved.getFilePath()).isNull();
        verify(versions, never()).markCurrentAsOld(anyLong());
        verify(operators, never()).saveAll(anyList());
    }

    /** The current version stubbed by previouslyDownloaded / currentVersion. */
    private FeedVersion current;

    /**
     * A previously good feed: its current version is DATED_ZIP, stored at feeds/{id}/{sha256}.zip on disk
     * (the DB side of it lives in the mocked repository).
     */
    private Path previouslyDownloaded(long id, String sourceId) throws Exception {
        FeedSource source = feed(id, sourceId);
        Path existing = fileOf(id, DATED_ZIP);
        Files.createDirectories(existing.getParent());
        Files.write(existing, DATED_ZIP);
        currentVersion(source.getFeed(), existing, DATED_ZIP);
        return existing;
    }

    private void currentVersion(Feed feed, Path file, byte[] content) throws Exception {
        current = TestEntities.current(feed, file.toString(), LocalDate.of(2028, 5, 31));
        current.setSha256(sha256(content));
        when(versions.findByFeedIdAndStatus(feed.getId(), FeedVersion.CURRENT)).thenReturn(Optional.of(current));
    }

    /** Where download() stores a file: feeds/{feedId}/{sha256}.zip. */
    private static Path fileOf(long id, byte[] content) throws Exception {
        return FeedService.FEEDS_ROOT.resolve(String.valueOf(id)).resolve(sha256(content) + ".zip");
    }

    /** Files in feeds/{id}/ (empty if the folder doesn't exist). */
    private static List<Path> filesIn(long id) throws IOException {
        Path dir = FeedService.FEEDS_ROOT.resolve(String.valueOf(id));
        if (!Files.isDirectory(dir)) {
            return List.of();
        }
        try (Stream<Path> files = Files.list(dir)) {
            return files.toList();
        }
    }

    // ---- versioned files: unchanged, move + switch, rollback ----

    @Test
    void sameFileAsTheCurrentVersionIsUnchangedNoNewRowNoFileChangesTempDeleted() throws Exception {
        Path existing = previouslyDownloaded(990019L, "mdb-dated"); // the source sends DATED_ZIP again
        FileTime before = FileTime.fromMillis(1_600_000_000_000L);
        Files.setLastModifiedTime(existing, before);

        DownloadResult result = service.download(990019L);

        assertThat(result.unchanged()).isTrue();
        assertThat(result.version()).isSameAs(current);
        assertThat(requestedPaths).containsExactly("/mdb-dated/latest.zip");
        assertThat(filesIn(990019L)).containsExactly(existing);
        assertThat(Files.getLastModifiedTime(existing)).as("the file was not replaced").isEqualTo(before);
        assertThat(partFiles(990019L)).isEmpty();
        verify(versions, never()).save(any());
        verify(versions, never()).markCurrentAsOld(anyLong());
        verify(operators, never()).saveAll(anyList());
        verify(versions, never()).findByFeedIdAndStatusInOrderByIdDesc(anyLong(), any());
        assertThat(current.getStatus()).isEqualTo(FeedVersion.CURRENT);
    }

    @Test
    void sameShaButTheCurrentFileIsMissingIsDownloadedAgainAsANewVersion() throws Exception {
        // otherwise a deleted file could never be repaired: every update would say "unchanged"
        FeedSource source = feed(990020L, "mdb-dated");
        currentVersion(source.getFeed(), fileOf(990020L, DATED_ZIP), DATED_ZIP); // row exists, file doesn't

        DownloadResult result = service.download(990020L);

        assertThat(result.unchanged()).isFalse();
        assertThat(fileOf(990020L, DATED_ZIP)).hasBinaryContent(DATED_ZIP);
        assertThat(savedOnce().getStatus()).isEqualTo(FeedVersion.CURRENT);
    }

    @Test
    void newFileIsMovedToFeedsIdShaZipAndThePreviousCurrentIsDemoted() throws Exception {
        Path previous = previouslyDownloaded(990021L, "mdb-ok"); // current = DATED_ZIP, the source now sends ZIP_BYTES

        DownloadResult result = service.download(990021L);

        assertThat(result.unchanged()).isFalse();
        Path target = fileOf(990021L, ZIP_BYTES);
        assertThat(target).hasBinaryContent(ZIP_BYTES);
        assertThat(result.version().getFilePath()).isEqualTo(target.toString());
        assertThat(result.version().getSha256()).isEqualTo(sha256(ZIP_BYTES));
        assertThat(previous).as("the previous file stays: retention keeps the newest 2").hasBinaryContent(DATED_ZIP);
        assertThat(filesIn(990021L)).containsExactlyInAnyOrder(previous, target);
        assertThat(partFiles(990021L)).isEmpty();
        InOrder order = inOrder(versions);
        order.verify(versions).markCurrentAsOld(990021L);
        order.verify(versions).save(result.version());
        // retention runs after the switch
        order.verify(versions).findByFeedIdAndStatusInOrderByIdDesc(990021L, List.of(FeedVersion.CURRENT, FeedVersion.OLD));
    }

    @Test
    void goingBackToAnOlderFileReusesItsPathAndMakesANewVersion() throws Exception {
        // A -> B -> A: the current version is B (ZIP_BYTES) and A's file (DATED_ZIP) is still on disk from an old version
        FeedSource source = feed(990022L, "mdb-dated");
        Path fileB = fileOf(990022L, ZIP_BYTES);
        Path fileA = fileOf(990022L, DATED_ZIP);
        Files.createDirectories(fileB.getParent());
        Files.write(fileB, ZIP_BYTES);
        Files.write(fileA, DATED_ZIP);
        currentVersion(source.getFeed(), fileB, ZIP_BYTES);

        DownloadResult result = service.download(990022L);

        assertThat(result.unchanged()).isFalse();
        assertThat(result.version().getFilePath()).isEqualTo(fileA.toString());
        assertThat(fileA).hasBinaryContent(DATED_ZIP);
        assertThat(filesIn(990022L)).containsExactlyInAnyOrder(fileA, fileB);
        verify(versions).markCurrentAsOld(990022L);
    }

    @Test
    void whenTheSwitchFailsTheMovedFileIsDeletedAndAFailedRowIsStored() throws Exception {
        feed(990023L, "mdb-ok");
        DataAccessResourceFailureException dbDown = new DataAccessResourceFailureException("database down");
        when(versions.save(any(FeedVersion.class))).thenAnswer(inv -> {
            FeedVersion v = inv.getArgument(0);
            if (FeedVersion.CURRENT.equals(v.getStatus())) {
                throw dbDown; // the save inside the switch transaction
            }
            return v;
        });

        Throwable thrown = catchThrowable(() -> service.download(990023L));

        assertThat(thrown).isSameAs(dbDown);
        Path moved = fileOf(990023L, ZIP_BYTES);
        assertThat(moved).as("no file without a row pointing at it").doesNotExist();
        assertThat(partFiles(990023L)).isEmpty();
        verify(versions).existsByFilePath(moved.toString());
        ArgumentCaptor<FeedVersion> saved = ArgumentCaptor.forClass(FeedVersion.class);
        verify(versions, times(2)).save(saved.capture()); // the failing current one, then the failed row
        assertThat(saved.getAllValues().get(1).getStatus()).isEqualTo(FeedVersion.FAILED);
        assertThat(saved.getAllValues().get(1).getFilePath()).isNull();
        verify(versions, never()).findByFeedIdAndStatusInOrderByIdDesc(anyLong(), any());
    }

    @Test
    void whenTheSwitchFailsAFileAnotherVersionStillUsesIsKept() throws Exception {
        // A -> B -> A again, but the switch fails: A's file belongs to the old version too, so it must stay
        feed(990024L, "mdb-dated");
        Path fileA = fileOf(990024L, DATED_ZIP);
        Files.createDirectories(fileA.getParent());
        Files.write(fileA, DATED_ZIP);
        when(versions.existsByFilePath(fileA.toString())).thenReturn(true);
        when(versions.markCurrentAsOld(990024L)).thenThrow(new DataAccessResourceFailureException("database down"));

        assertThatThrownBy(() -> service.download(990024L)).isInstanceOf(DataAccessResourceFailureException.class);

        assertThat(fileA).hasBinaryContent(DATED_ZIP);
        assertThat(savedOnce().getStatus()).isEqualTo(FeedVersion.FAILED);
    }

    @Test
    void aFailingRetentionNeverFailsTheDownload() throws Exception {
        feed(990025L, "mdb-ok");
        when(versions.findByFeedIdAndStatusInOrderByIdDesc(anyLong(), any())).thenThrow(new IllegalStateException("boom"));

        DownloadResult result = service.download(990025L);

        assertThat(result.unchanged()).isFalse();
        assertThat(fileOf(990025L, ZIP_BYTES)).exists();
    }

    @Test
    void connectionDroppedMidBodyStoresAFailedVersionOnceAndRethrowsTheIOExceptionUnwrapped() throws Exception {
        Path existing = previouslyDownloaded(990010L, "mdb-drop");

        Object[] r = downloadAndTakeInterruptFlag(990010L);
        Throwable thrown = (Throwable) r[0];

        assertThat((boolean) r[1]).as("an IOException must not set the interrupt flag").isFalse();
        assertThat(thrown).isInstanceOf(IOException.class).isNotInstanceOf(ResponseStatusException.class);
        assertThat(requestedPaths).containsExactly("/mdb-drop/latest.zip");
        assertFailedAndCurrentUntouched(990010L, existing);
    }

    @Test
    void ioExceptionFromTheHttpClientIsRethrownAsTheSameInstanceAndLeavesNoInterruptFlag() throws Exception {
        Path existing = previouslyDownloaded(990011L, "mdb-ok");
        HttpClient client = mock(HttpClient.class);
        IOException boom = new IOException("connection reset");
        when(client.send(any(), any())).thenThrow(boom);
        ReflectionTestUtils.setField(service, "client", client);

        Object[] r = downloadAndTakeInterruptFlag(990011L);
        Throwable thrown = (Throwable) r[0];

        assertThat((boolean) r[1]).as("an IOException must not set the interrupt flag").isFalse();
        assertThat(thrown).isSameAs(boom);
        assertThat(requestedPaths).isEmpty();
        assertFailedAndCurrentUntouched(990011L, existing);
    }

    @Test
    void interruptedExceptionFromTheHttpClientStoresFailedRethrowsTheSameInstanceAndRestoresTheFlag() throws Exception {
        Path existing = previouslyDownloaded(990012L, "mdb-ok");
        HttpClient client = mock(HttpClient.class);
        InterruptedException interrupted = new InterruptedException("stop");
        when(client.send(any(), any())).thenThrow(interrupted);
        ReflectionTestUtils.setField(service, "client", client);

        Object[] r = downloadAndTakeInterruptFlag(990012L);
        Throwable thrown = (Throwable) r[0];

        assertThat((boolean) r[1]).as("interrupt flag restored after the throw").isTrue();
        assertThat(thrown).isSameAs(interrupted);
        assertFailedAndCurrentUntouched(990012L, existing);
    }

    @Test
    void realInterruptDuringSendStoresFailedRethrowsAndRestoresTheFlag() throws Exception {
        Path existing = previouslyDownloaded(990013L, "mdb-ok");

        Thread.currentThread().interrupt();
        Object[] r = downloadAndTakeInterruptFlag(990013L);
        Throwable thrown = (Throwable) r[0];

        System.out.println("[r19] interrupt flag after download(): " + r[1] + ", thrown: " + thrown);
        assertThat((boolean) r[1]).as("interrupt flag restored after the throw").isTrue();
        assertThat(thrown).isInstanceOf(InterruptedException.class);
        assertFailedAndCurrentUntouched(990013L, existing);
    }

    @Test
    void failedSaveRunsWithTheFlagClearAndTheFlagIsRestoredOnlyAfterIt() throws Exception {
        Path existing = previouslyDownloaded(990014L, "mdb-ok");
        HttpClient client = mock(HttpClient.class);
        InterruptedException interrupted = new InterruptedException("stop");
        when(client.send(any(), any())).thenThrow(interrupted);
        ReflectionTestUtils.setField(service, "client", client);
        List<Boolean> flagDuringSave = new CopyOnWriteArrayList<>();
        when(versions.save(any(FeedVersion.class))).thenAnswer(inv -> {
            flagDuringSave.add(Thread.currentThread().isInterrupted());
            return inv.getArgument(0);
        });

        Object[] r = downloadAndTakeInterruptFlag(990014L);

        // the save talks to the database, so it must not run with the flag set (a set flag can abort a blocking pool wait)
        assertThat(flagDuringSave).containsExactly(false);
        assertThat((boolean) r[1]).isTrue();
        assertThat(r[0]).isSameAs(interrupted);
        assertFailedAndCurrentUntouched(990014L, existing);
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
            for (Path file : filesIn(id)) {
                Files.deleteIfExists(file);
            }
            Files.deleteIfExists(FeedService.FEEDS_ROOT.resolve(String.valueOf(id)));
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
