package com.example.RoTransit.service;

import com.example.RoTransit.dto.FeedOperator;
import com.example.RoTransit.dto.FeedStatus;
import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedSource;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.entity.Operator;
import com.example.RoTransit.repository.FeedRepository;
import com.example.RoTransit.repository.FeedSourceRepository;
import com.example.RoTransit.repository.FeedVersionRepository;
import com.example.RoTransit.repository.OperatorRepository;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * FeedVersionService against the real Postgres schema: the current/old switch, failures that must not demote the
 * current version, and the one-query operator names. Uses the seeded feed 1 (Brasov) and its priority-1 source.
 * @Transactional rolls every row back after each test.
 */
@SpringBootTest
@Transactional
class FeedVersionSwitchTest {

    @Autowired
    private FeedVersionService versionService;

    @Autowired
    private FeedRepository feeds;

    @Autowired
    private FeedSourceRepository sources;

    @Autowired
    private FeedVersionRepository versions;

    @Autowired
    private OperatorRepository operators;

    @Autowired
    private EntityManager entityManager;

    @Autowired
    private JdbcTemplate jdbc;

    private Feed feed;
    private FeedSource source;

    @BeforeEach
    void setUp() {
        feed = feeds.findById(1L).orElseThrow();
        source = sources.findByFeedIdAndPriority(1L, 1).orElseThrow();
    }

    private FeedVersion download(LocalDate expiresOn) {
        FeedVersion version = new FeedVersion();
        version.setFeed(feed);
        version.setSource(source);
        version.setFilePath("feeds/1.zip");
        version.setSha256("0".repeat(64));
        version.setExpiresOn(expiresOn);
        version.setDownloadedAt(Instant.now());
        return version;
    }

    private Operator operator(String name) {
        Operator operator = new Operator();
        operator.setName(name);
        return operator;
    }

    /** The status as stored in the database (the bulk update bypasses the entities Hibernate keeps in memory). */
    private String statusInDb(FeedVersion version) {
        entityManager.flush();
        return jdbc.queryForObject("select status from feeds.feed_version where id = ?", String.class, version.getId());
    }

    @Test
    void aNewDownloadBecomesCurrentAndThePreviousCurrentBecomesOld() {
        FeedVersion first = versionService.saveAsCurrent(download(LocalDate.of(2027, 1, 1)), List.of(operator("First Co")));
        assertThat(statusInDb(first)).isEqualTo("current");

        FeedVersion second = versionService.saveAsCurrent(download(LocalDate.of(2027, 6, 1)), List.of(operator("Second Co")));

        assertThat(statusInDb(first)).isEqualTo("old");
        assertThat(statusInDb(second)).isEqualTo("current");
        entityManager.clear(); // read back from the database, not from Hibernate's memory
        assertThat(versions.findByFeedIdAndStatus(1L, FeedVersion.CURRENT)).get()
                .extracting(FeedVersion::getId).isEqualTo(second.getId());
        assertThat(versions.findCurrentByFeedId().get(1L).getExpiresOn()).isEqualTo(LocalDate.of(2027, 6, 1));
    }

    @Test
    void aFailedAttemptIsStoredButDoesNotDemoteTheCurrentVersion() {
        FeedVersion current = versionService.saveAsCurrent(download(LocalDate.of(2027, 1, 1)), List.of());

        FeedVersion failed = versionService.saveFailed(feed, source, Instant.now());

        assertThat(statusInDb(current)).isEqualTo("current");
        assertThat(statusInDb(failed)).isEqualTo("failed");
        entityManager.clear();
        FeedVersion currentNow = versions.findCurrentByFeedId().get(1L);
        FeedVersion latestNow = versions.findLatestByFeedId().get(1L);
        assertThat(currentNow.getId()).isEqualTo(current.getId());
        assertThat(latestNow.getId()).isEqualTo(failed.getId());
        assertThat(latestNow.getFilePath()).isNull();
        // the admin list shows "failed" but keeps the current version's dates
        FeedStatus status = FeedStatus.from(feeds.findById(1L).orElseThrow(), currentNow, latestNow);
        assertThat(status.status()).isEqualTo("failed");
        assertThat(status.expiresOn()).isEqualTo(LocalDate.of(2027, 1, 1));
    }

    @Test
    void publicOperatorNamesComeOnlyFromCurrentVersions() {
        versionService.saveAsCurrent(download(LocalDate.of(2027, 1, 1)), List.of(operator("Old Co")));
        versionService.saveAsCurrent(download(LocalDate.of(2027, 6, 1)), List.of(operator("New Co"), operator("Partner Co")));
        versionService.saveFailed(feed, source, Instant.now());
        entityManager.flush();
        entityManager.clear();

        List<FeedOperator> names = operators.findCurrentOperatorNames();

        assertThat(names).filteredOn(o -> o.feedId() == 1L).extracting(FeedOperator::name)
                .containsExactly("New Co", "Partner Co");
    }

    @Test
    void theDatabaseRefusesASecondCurrentVersionForTheSameFeed() {
        versionService.saveAsCurrent(download(LocalDate.of(2027, 1, 1)), List.of());
        entityManager.flush();

        // bypassing FeedVersionService: the partial unique index in V1 is the last line of defence
        assertThatThrownBy(() -> jdbc.update("insert into feeds.feed_version (feed_id, downloaded_at, status)"
                + " values (1, now(), 'current')"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void aFeedCanGoBackToAnOlderFileTheSameShaIsAllowedTwice() {
        // A -> B -> A: no UNIQUE(feed_id, sha256) on purpose, the second A is a new row sharing A's file
        FeedVersion a = download(LocalDate.of(2027, 1, 1));
        a.setSha256("a".repeat(64));
        a.setFilePath("feeds/1/" + "a".repeat(64) + ".zip");
        FeedVersion first = versionService.saveAsCurrent(a, List.of());
        FeedVersion b = download(LocalDate.of(2027, 2, 1));
        b.setSha256("b".repeat(64));
        FeedVersion second = versionService.saveAsCurrent(b, List.of());
        FeedVersion againA = download(LocalDate.of(2027, 1, 1));
        againA.setSha256("a".repeat(64));
        againA.setFilePath(a.getFilePath());
        FeedVersion third = versionService.saveAsCurrent(againA, List.of());

        assertThat(statusInDb(first)).isEqualTo("old");
        assertThat(statusInDb(second)).isEqualTo("old");
        assertThat(statusInDb(third)).isEqualTo("current");
        assertThat(versions.existsByFilePath(a.getFilePath())).isTrue();
    }
}
