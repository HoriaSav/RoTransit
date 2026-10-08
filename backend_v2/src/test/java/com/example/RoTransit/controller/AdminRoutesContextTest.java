package com.example.RoTransit.controller;

import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import com.jayway.jsonpath.JsonPath;
import jakarta.servlet.Filter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.WebApplicationContext;

import java.nio.charset.StandardCharsets;
import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Route mapping and GET /admin/feeds against the real application context and the real Postgres
 * (same DB as RoTransitApplicationTests). FeedService and FeedUpdateJob are mocked so a wrongly mapped route can
 * never download or update anything; @Transactional rolls back every probe row (MockMvc runs in the test thread).
 * The real Spring Security filter chain is applied (MockMvc + springSecurityFilterChain), so requests carry HTTP Basic
 * credentials for the admin user (test-only password from src/test/resources/config/application.properties).
 */
@SpringBootTest
@Transactional
class AdminRoutesContextTest {

    @Autowired
    private WebApplicationContext context;

    @Autowired
    private JdbcTemplate jdbc;

    @MockitoBean
    private FeedService feedService;

    @MockitoBean
    private FeedUpdateJob feedUpdateJob;

    @Value("${spring.security.user.name}")
    private String adminUser;

    @Value("${spring.security.user.password}")
    private String adminPassword;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .addFilters(context.getBean("springSecurityFilterChain", Filter.class))
                .build();
    }

    private String basicAuth() {
        return "Basic " + Base64.getEncoder().encodeToString((adminUser + ":" + adminPassword).getBytes(StandardCharsets.UTF_8));
    }

    /** Rows in all tables a wrongly mapped POST /admin/feeds could write to. */
    private int rowCount() {
        return jdbc.queryForObject("select (select count(*) from feeds.city) + (select count(*) from feeds.feed)"
                + " + (select count(*) from feeds.feed_source) + (select count(*) from feeds.feed_version)", Integer.class);
    }

    private int feedCount() {
        return jdbc.queryForObject("select count(*) from feeds.feed", Integer.class);
    }

    @ParameterizedTest(name = "{0} {1} -> admin {2}, anonymous {3}")
    @CsvSource({
            // routes that moved: the old paths must be gone. Since SecurityConfig they never reach MVC:
            // anyRequest().denyAll() answers 403 for the authenticated admin and 401 for anonymous (was 404 before security)
            "GET,  /feeds,            403, 401",
            "POST, /feeds,            403, 401",
            "GET,  /feeds/1,          403, 401",
            "POST, /feeds/1/download, 403, 401",
            "POST, /feeds/update,     403, 401",
            "GET,  /feeds/1/expires,  403, 401",
            "GET,  /feeds/1/file,     403, 401",
            // new routes must not answer under the other prefix (/api/** is permitAll, so MVC decides: 404/405)
            "GET,  /api/feeds/1/expires,   404, 404",
            "POST, /api/feeds/update,      404, 404",
            "POST, /api/feeds/1/download,  404, 404",
            "GET,  /api/feeds/1,           404, 404",
            "POST, /api/feeds,             405, 405",
            // /admin/** needs ADMIN first, then MVC has no such route
            "GET,  /admin/feeds/1/file,    404, 401"
    })
    void oldAndWrongPrefixPathsAreNotMappedAndHaveNoSideEffects(String method, String path, int asAdmin, int anonymous) throws Exception {
        int before = rowCount();
        String body = "{\"cityName\":\"OldPathProbe\",\"companyName\":\"X\",\"sourceId\":\"mdb-old-path\"}";

        mvc.perform(request(HttpMethod.valueOf(method), path)
                        .header(HttpHeaders.AUTHORIZATION, basicAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().is(asAdmin));
        mvc.perform(request(HttpMethod.valueOf(method), path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().is(anonymous));

        assertThat(rowCount()).isEqualTo(before);
        verifyNoInteractions(feedService, feedUpdateJob);
    }

    @Test
    void statusListFromTheDatabaseIsNullsFirstThenAscendingWithDaysLeftAndNoLocalPath() throws Exception {
        LocalDate today = LocalDate.now();
        insert("CtxNull", null);
        insert("CtxPast", today.minusDays(3));
        insert("CtxTieA", today.plusDays(10));
        insert("CtxToday", today);
        insert("CtxTieB", today.plusDays(10));
        int total = feedCount();

        String json = mvc.perform(get("/admin/feeds").header(HttpHeaders.AUTHORIZATION, basicAuth()))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        List<Map<String, Object>> list = JsonPath.read(json, "$");

        assertThat(list).hasSize(total);
        for (Map<String, Object> entry : list) {
            assertThat(entry).containsOnlyKeys("id", "cityName", "companyName", "status", "downloadedAt", "expiresOn", "daysLeft");
        }
        // whole list (real rows + probes): every null before every date, dates never decreasing
        List<LocalDate> expires = new ArrayList<>();
        for (Map<String, Object> entry : list) {
            expires.add(entry.get("expiresOn") == null ? null : LocalDate.parse((String) entry.get("expiresOn")));
        }
        int firstDate = 0;
        while (firstDate < expires.size() && expires.get(firstDate) == null) firstDate++;
        assertThat(expires.subList(firstDate, expires.size())).doesNotContainNull().isSorted();

        Map<String, Object> nul = byCity(list, "CtxNull");
        assertThat(nul.get("daysLeft")).isNull();
        assertThat(nul.get("status")).isEqualTo("new");
        assertThat(list.indexOf(nul)).isLessThan(firstDate);
        assertThat(((Number) byCity(list, "CtxPast").get("daysLeft")).longValue()).isEqualTo(-3);
        assertThat(((Number) byCity(list, "CtxToday").get("daysLeft")).longValue()).isZero();
        assertThat(((Number) byCity(list, "CtxTieA").get("daysLeft")).longValue()).isEqualTo(10);
        assertThat(((Number) byCity(list, "CtxTieB").get("daysLeft")).longValue()).isEqualTo(10);
        assertThat(list.indexOf(byCity(list, "CtxPast"))).isLessThan(list.indexOf(byCity(list, "CtxToday")));
        assertThat(list.indexOf(byCity(list, "CtxToday"))).isLessThan(list.indexOf(byCity(list, "CtxTieA")));
        verifyNoInteractions(feedService, feedUpdateJob);
    }

    @Test
    void statusListTieBreaksByIdEvenWhenTheDatabaseReturnsRowsOutOfIdOrder() throws Exception {
        // explicit ids inserted in descending order, so a plain findAll() (heap order) may return them high-to-low
        LocalDate same = LocalDate.now().plusDays(500);
        insertWithId(9_000_003L, "CtxSameC", same);
        insertWithId(9_000_002L, "CtxSameB", same);
        insertWithId(9_000_001L, "CtxSameA", same);
        insertWithId(9_000_012L, "CtxNullB", null);
        insertWithId(9_000_011L, "CtxNullA", null);

        String json = mvc.perform(get("/admin/feeds").header(HttpHeaders.AUTHORIZATION, basicAuth()))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        List<Map<String, Object>> list = JsonPath.read(json, "$");

        assertThat(list.indexOf(byCity(list, "CtxSameA"))).isLessThan(list.indexOf(byCity(list, "CtxSameB")));
        assertThat(list.indexOf(byCity(list, "CtxSameB"))).isLessThan(list.indexOf(byCity(list, "CtxSameC")));
        assertThat(list.indexOf(byCity(list, "CtxNullA"))).isLessThan(list.indexOf(byCity(list, "CtxNullB")));
        // whole list: wherever two neighbours share expiresOn (null included), ids ascend
        for (int i = 1; i < list.size(); i++) {
            Map<String, Object> prev = list.get(i - 1), cur = list.get(i);
            if (java.util.Objects.equals(prev.get("expiresOn"), cur.get("expiresOn"))) {
                assertThat(((Number) prev.get("id")).longValue()).as("tie at %s", cur.get("expiresOn"))
                        .isLessThan(((Number) cur.get("id")).longValue());
            }
        }
    }

    /** A feed with explicit ids (city id = feed id); with a date it also gets a current version. */
    private void insertWithId(long id, String city, LocalDate expiresOn) {
        jdbc.update("insert into feeds.city (id, name) values (?, ?)", id, city);
        jdbc.update("insert into feeds.feed (id, city_id, name) values (?, ?, ?)", id, id, city + "Co");
        if (expiresOn != null) {
            insertCurrentVersion(id, expiresOn);
        }
    }

    /**
     * A feed in its own city. Without a date it has no versions yet ("new"); with a date it gets a current version
     * whose file_path must never leak into the JSON.
     */
    private void insert(String city, LocalDate expiresOn) {
        Long cityId = jdbc.queryForObject("insert into feeds.city (name) values (?) returning id", Long.class, city);
        Long feedId = jdbc.queryForObject("insert into feeds.feed (city_id, name) values (?, ?) returning id", Long.class,
                cityId, city + "Co");
        if (expiresOn != null) {
            insertCurrentVersion(feedId, expiresOn);
        }
    }

    private void insertCurrentVersion(long feedId, LocalDate expiresOn) {
        jdbc.update("insert into feeds.feed_version (feed_id, file_path, expires_on, downloaded_at, status)"
                        + " values (?, 'feeds/should-not-leak.zip', ?, now(), 'current')",
                feedId, Date.valueOf(expiresOn));
    }

    private static Map<String, Object> byCity(List<Map<String, Object>> list, String city) {
        return list.stream().filter(e -> city.equals(e.get("cityName"))).findFirst().orElseThrow();
    }
}
