package com.example.RoTransit.controller;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.WebApplicationContext;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * POST /admin/feeds against the real Postgres schema (feeds.feed.status is NOT NULL DEFAULT 'new').
 * Same database as RoTransitApplicationTests. @Transactional makes the test roll back, so no row is left behind:
 * MockMvc runs in the test thread, so the repository save joins the test transaction.
 */
@SpringBootTest
@Transactional
class CreateFeedPersistenceTest {

    @Autowired
    private WebApplicationContext context;

    @Autowired
    private JdbcTemplate jdbc;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.webAppContextSetup(context).build();
    }

    @Test
    void postWithoutStatusPersistsStatusNew() throws Exception {
        MvcResult result = mvc.perform(post("/admin/feeds")
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
