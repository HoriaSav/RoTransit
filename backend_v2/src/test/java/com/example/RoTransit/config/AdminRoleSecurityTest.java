package com.example.RoTransit.config;

import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedSourceRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import com.example.RoTransit.repository.OperatorRepository;
import com.example.RoTransit.service.FeedService;
import com.example.RoTransit.service.FeedUpdateJob;
import jakarta.servlet.Filter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;

import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The same Boot-configured user, but with role USER instead of ADMIN (test property): a correctly authenticated
 * user without ADMIN must get 403 on /admin/**, keep access to /api/**, and stay denied elsewhere.
 * Uses the real springSecurityFilterChain via MockMvc; no spring-security-test dependency needed.
 */
@SpringBootTest
@TestPropertySource(properties = "spring.security.user.roles=USER")
class AdminRoleSecurityTest {

    @Autowired
    private WebApplicationContext context;

    @Value("${spring.security.user.name}")
    private String user;

    @Value("${spring.security.user.password}")
    private String password;

    @MockitoBean
    private FeedRepository repo;

    @MockitoBean
    private FeedSourceRepository sources;

    @MockitoBean
    private FeedVersionRepository versions;

    @MockitoBean
    private OperatorRepository operators;

    @MockitoBean
    private FeedService feedService;

    @MockitoBean
    private FeedUpdateJob feedUpdateJob;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        when(repo.findAll()).thenReturn(List.of());
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .addFilters(context.getBean("springSecurityFilterChain", Filter.class))
                .build();
    }

    @ParameterizedTest(name = "{0} {1} -> {2}")
    @CsvSource({
            "GET,  /admin/feeds,            403",
            "GET,  /admin/feeds/1,          403",
            "GET,  /admin/feeds/1/expires,  403",
            "POST, /admin/feeds/update,     403",
            "POST, /admin/feeds,            403",
            "POST, /admin/feeds/1/download, 403",
            "GET,  /api/feeds,              200",
            "GET,  /foo,                    403"
    })
    void userWithoutAdminRole(String method, String path, int expected) throws Exception {
        String auth = "Basic " + Base64.getEncoder().encodeToString((user + ":" + password).getBytes(StandardCharsets.UTF_8));

        mvc.perform(request(HttpMethod.valueOf(method), path)
                        .header(HttpHeaders.AUTHORIZATION, auth)
                        .contentType("application/json")
                        .content("{\"cityName\":\"RoleProbe\",\"companyName\":\"X\",\"sourceId\":\"mdb-role\"}"))
                .andExpect(status().is(expected));

        verifyNoInteractions(feedService, feedUpdateJob, sources, versions);
    }
}
