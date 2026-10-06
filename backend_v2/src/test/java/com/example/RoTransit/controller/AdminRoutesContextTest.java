package com.example.RoTransit.controller;

import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.WebApplicationContext;

import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
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

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.webAppContextSetup(context).build();
    }

    private int rowCount() {
        return jdbc.queryForObject("select count(*) from feeds.feed", Integer.class);
    }

    @ParameterizedTest(name = "{0} {1} -> {2}")
    @CsvSource({
            // routes that moved: the old paths must be gone
            "GET,  /feeds,            404",
            "POST, /feeds,            404",
            "GET,  /feeds/1,          404",
            "POST, /feeds/1/download, 404",
            "POST, /feeds/update,     404",
            "GET,  /feeds/1/expires,  404",
            "GET,  /feeds/1/file,     404",
            // new routes must not answer under the other prefix
            "GET,  /api/feeds/1/expires,   404",
            "POST, /api/feeds/update,      404",
            "POST, /api/feeds/1/download,  404",
            "GET,  /api/feeds/1,           404",
            "POST, /api/feeds,             405",
            "GET,  /admin/feeds/1/file,    404"
    })
    void oldAndWrongPrefixPathsAreNotMappedAndHaveNoSideEffects(String method, String path, int expected) throws Exception {
        int before = rowCount();

        mvc.perform(request(HttpMethod.valueOf(method), path)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"cityName\":\"OldPathProbe\",\"companyName\":\"X\",\"sourceId\":\"mdb-old-path\"}"))
                .andExpect(status().is(expected));

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
        int total = rowCount();

        String json = mvc.perform(get("/admin/feeds"))
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

    private void insert(String city, LocalDate expiresOn) {
        jdbc.update("insert into feeds.feed (city_name, company_name, source_id, local_path, expires_on) values (?, ?, ?, ?, ?)",
                city, city + "Co", "mdb-ctx-" + city, "feeds/should-not-leak.zip", expiresOn == null ? null : Date.valueOf(expiresOn));
    }

    private static Map<String, Object> byCity(List<Map<String, Object>> list, String city) {
        return list.stream().filter(e -> city.equals(e.get("cityName"))).findFirst().orElseThrow();
    }
}
