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
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
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
 * FEEDS_ROOT is the relative path "feeds", so the test uses ids 990001..990004 inside ./feeds and deletes them afterwards.
 */
class FeedServiceDownloadTest {

    private static final String HOST = "files.mobilitydatabase.org";
    private static final byte[] ZIP_BYTES = "PK\u0003\u0004 tiny fake zip for FeedServiceDownloadTest".getBytes(StandardCharsets.ISO_8859_1);
    private static final List<Long> IDS = List.of(990001L, 990002L, 990003L, 990004L);

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
        cleanFeedsDir();
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
    void non200SourceGives502AndLeavesNoTargetAndNoTempFile() throws Exception {
        Feed feed = feed(990002L, "mdb-does-not-exist-xyz");

        assertThatThrownBy(() -> service.download(990002L))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(e -> assertThat(((ResponseStatusException) e).getStatusCode().value()).isEqualTo(502));

        assertThat(FeedService.FEEDS_ROOT.resolve("990002.zip")).doesNotExist();
        assertThat(partFiles(990002L)).isEmpty();
        assertThat(feed.getStatus()).isEqualTo("new");
        assertThat(feed.getLocalPath()).isNull();
        verify(repo, never()).save(any());
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
