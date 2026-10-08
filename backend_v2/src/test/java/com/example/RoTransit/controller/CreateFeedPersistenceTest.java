package com.example.RoTransit.controller;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import jakarta.servlet.Filter;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.WebApplicationContext;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * POST /admin/feeds against the real Postgres schema: it must create the city (only if missing), the feed and its
 * priority-1 mobilitydb source.
 * Same database as RoTransitApplicationTests. @Transactional makes the test roll back, so no row is left behind:
 * MockMvc runs in the test thread, so the repository save joins the test transaction.
 * The real Spring Security filter chain is applied, so the request authenticates with HTTP Basic as the admin user
 * (test-only password from src/test/resources/config/application.properties).
 */
@SpringBootTest
@Transactional
class CreateFeedPersistenceTest {

    @Autowired
    private WebApplicationContext context;

    @Autowired
    private JdbcTemplate jdbc;

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

    private MvcResult create(String cityName, String companyName, String sourceId) throws Exception {
        return mvc.perform(post("/admin/feeds")
                        .header(HttpHeaders.AUTHORIZATION, basicAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"cityName":"%s","companyName":"%s","sourceId":"%s"}
                                """.formatted(cityName, companyName, sourceId)))
                .andExpect(status().isOk())
                .andReturn();
    }

    private long idOf(MvcResult result) throws Exception {
        Number id = com.jayway.jsonpath.JsonPath.read(result.getResponse().getContentAsString(), "$.id");
        return id.longValue();
    }

    @Test
    void postCreatesCityFeedAndPriorityOneSourceWithStatusNew() throws Exception {
        MvcResult result = mvc.perform(post("/admin/feeds")
                        .header(HttpHeaders.AUTHORIZATION, basicAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"cityName":"RollbackTestCity","companyName":"RollbackTestCo","sourceId":"mdb-rollback-test-r14"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("new"))
                .andExpect(jsonPath("$.cityName").value("RollbackTestCity"))
                .andExpect(jsonPath("$.companyName").value("RollbackTestCo"))
                .andExpect(jsonPath("$.sourceId").value("mdb-rollback-test-r14"))
                .andExpect(jsonPath("$.localPath").doesNotExist())
                .andReturn();

        long id = idOf(result);
        assertThat(id).as("seeded feeds keep ids 1..13, so new ones come after them").isGreaterThan(13);
        Map<String, Object> feed = jdbc.queryForMap(
                "select f.name, c.name as city from feeds.feed f join feeds.city c on c.id = f.city_id where f.id = ?", id);
        assertThat(feed.get("name")).isEqualTo("RollbackTestCo");
        assertThat(feed.get("city")).isEqualTo("RollbackTestCity");
        List<Map<String, Object>> sources = jdbc.queryForList(
                "select kind, ref, priority from feeds.feed_source where feed_id = ?", id);
        assertThat(sources).containsExactly(Map.of("kind", "mobilitydb", "ref", "mdb-rollback-test-r14", "priority", 1));
        assertThat(jdbc.queryForObject("select count(*) from feeds.feed_version where feed_id = ?", Integer.class, id))
                .as("nothing downloaded yet").isZero();
    }

    @Test
    void postForAnExistingCityReusesItInsteadOfCreatingASecondOne() throws Exception {
        long first = idOf(create("RollbackTwoFeedsCity", "FirstCo", "mdb-rollback-first"));
        long second = idOf(create("RollbackTwoFeedsCity", "SecondCo", "mdb-rollback-second"));
        long seeded = idOf(create("Brasov", "RollbackBrasovCo", "mdb-rollback-brasov"));

        assertThat(jdbc.queryForObject("select count(*) from feeds.city where name = 'RollbackTwoFeedsCity'", Integer.class))
                .isEqualTo(1);
        assertThat(jdbc.queryForList("select distinct city_id from feeds.feed where id in (?, ?)", Long.class, first, second))
                .hasSize(1);
        assertThat(jdbc.queryForObject("select city_id from feeds.feed where id = ?", Long.class, seeded))
                .as("the seeded Brasov city").isEqualTo(1L);
    }
}
