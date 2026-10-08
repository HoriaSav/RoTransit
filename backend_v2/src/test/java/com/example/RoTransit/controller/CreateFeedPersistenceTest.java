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

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * POST /admin/feeds against the real Postgres schema (feeds.feed.status is NOT NULL DEFAULT 'new').
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

    @Test
    void postWithoutStatusPersistsStatusNew() throws Exception {
        MvcResult result = mvc.perform(post("/admin/feeds")
                        .header(HttpHeaders.AUTHORIZATION, basicAuth())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"cityName":"RollbackTestCity","companyName":"RollbackTestCo","sourceId":"mdb-rollback-test-r14"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("new"))
                .andExpect(jsonPath("$.localPath").doesNotExist())
                .andReturn();

        Number id = com.jayway.jsonpath.JsonPath.read(result.getResponse().getContentAsString(), "$.id");
        Map<String, Object> row = jdbc.queryForMap(
                "select status, source_id, local_path, expires_on from feeds.feed where id = ?", id.longValue());
        assertThat(row.get("status")).isEqualTo("new");
        assertThat(row.get("source_id")).isEqualTo("mdb-rollback-test-r14");
        assertThat(row.get("local_path")).isNull();
        assertThat(row.get("expires_on")).isNull();
    }
}
