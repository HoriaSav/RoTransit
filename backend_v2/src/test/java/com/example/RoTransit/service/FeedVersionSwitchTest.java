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
 * FeedVersionService against the real Postgres schema: the current/old switch, upcoming versions and their promotion,
 * failures that must not demote the current version, and the one-query operator names. Uses the seeded feed 1 (Brasov) and its priority-1 source.
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
        FeedStatus status = FeedStatus.from(feeds.findById(1L).orElseThrow(), currentNow, latestNow, null,
                LocalDate.of(2026, 10, 10));
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

    // ---- upcoming versions ----

    private long countInDb(String status) {
        entityManager.flush();
        return jdbc.queryForObject("select count(*) from feeds.feed_version where feed_id = 1 and status = ?",
                Long.class, status);
    }

    @Test
    void theDatabaseRefusesASecondUpcomingVersionForTheSameFeed() {
        versionService.saveAsUpcoming(download(LocalDate.of(2027, 1, 1)), List.of());
        entityManager.flush();

        assertThatThrownBy(() -> jdbc.update("insert into feeds.feed_version (feed_id, downloaded_at, status)"
                + " values (1, now(), 'upcoming')"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void aSecondUpcomingReplacesTheFirstWhichBecomesOld() {
        FeedVersion current = versionService.saveAsCurrent(download(LocalDate.of(2026, 12, 31)), List.of());
        FeedVersion first = versionService.saveAsUpcoming(download(LocalDate.of(2027, 3, 1)), List.of());
        FeedVersion second = versionService.saveAsUpcoming(download(LocalDate.of(2027, 6, 1)), List.of());

        assertThat(statusInDb(first)).isEqualTo("old");
        assertThat(statusInDb(second)).isEqualTo("upcoming");
        assertThat(statusInDb(current)).as("an upcoming download never touches current").isEqualTo("current");
    }

    @Test
    void promotionMakesTheUpcomingCurrentAndKeepsExactlyOneCurrent() {
        FeedVersion current = versionService.saveAsCurrent(download(LocalDate.of(2026, 12, 31)), List.of(operator("Old Co")));
        FeedVersion upcoming = versionService.saveAsUpcoming(download(LocalDate.of(2027, 6, 1)), List.of(operator("New Co")));
        entityManager.flush();

        assertThat(versionService.promoteUpcoming(1L)).get().extracting(FeedVersion::getId).isEqualTo(upcoming.getId());

        assertThat(statusInDb(current)).isEqualTo("old");
        assertThat(statusInDb(upcoming)).isEqualTo("current");
        assertThat(countInDb("current")).isEqualTo(1);
        assertThat(countInDb("upcoming")).isZero();
        entityManager.clear();
        // the public operator names follow the switch
        assertThat(operators.findCurrentOperatorNames()).filteredOn(o -> o.feedId() == 1L)
                .extracting(FeedOperator::name).containsExactly("New Co");
    }

    @Test
    void promotingWithoutAnUpcomingVersionChangesNothing() {
        FeedVersion current = versionService.saveAsCurrent(download(LocalDate.of(2026, 12, 31)), List.of());

        assertThat(versionService.promoteUpcoming(1L)).isEmpty();

        assertThat(statusInDb(current)).isEqualTo("current");
    }

    @Test
    void promotingAFeedThatNeverHadACurrentVersionWorksToo() {
        FeedVersion upcoming = versionService.saveAsUpcoming(download(LocalDate.of(2027, 6, 1)), List.of());

        versionService.promoteUpcoming(1L);

        assertThat(statusInDb(upcoming)).isEqualTo("current");
        assertThat(countInDb("current")).isEqualTo(1);
    }

    @Test
    void servedFromIsSetWhenAVersionBecomesCurrentAndNeverForAReplacedUpcoming() {
        FeedVersion current = versionService.saveAsCurrent(download(LocalDate.of(2026, 12, 31)), List.of());
        FeedVersion replaced = versionService.saveAsUpcoming(download(LocalDate.of(2027, 3, 1)), List.of());
        FeedVersion upcoming = versionService.saveAsUpcoming(download(LocalDate.of(2027, 6, 1)), List.of());
        entityManager.flush();
        assertThat(servedFromInDb(current)).isNotNull();
        assertThat(servedFromInDb(upcoming)).as("not served yet").isNull();

        versionService.promoteUpcoming(1L);

        assertThat(servedFromInDb(upcoming)).as("set on promotion").isNotNull();
        assertThat(servedFromInDb(current)).as("kept after it became old").isNotNull();
        assertThat(statusInDb(replaced)).isEqualTo("old");
        assertThat(servedFromInDb(replaced)).as("never was current").isNull();
    }

    private java.sql.Timestamp servedFromInDb(FeedVersion version) {
        entityManager.flush();
        return jdbc.queryForObject("select served_from from feeds.feed_version where id = ?",
                java.sql.Timestamp.class, version.getId());
    }

    // ---- failed-row cap and checked_at ----

    @Test
    void onlyTheNewest5FailedRowsAreKeptAndTheStatusIsStillFailed() {
        FeedVersion current = versionService.saveAsCurrent(download(LocalDate.of(2027, 1, 1)), List.of());
        List<FeedVersion> failed = new java.util.ArrayList<>();
        for (int i = 0; i < 7; i++) {
            failed.add(versionService.saveFailed(feed, source, Instant.now()));
        }
        entityManager.flush();
        entityManager.clear();

        List<Long> left = jdbc.queryForList(
                "select id from feeds.feed_version where feed_id = 1 and status = 'failed' order by id", Long.class);
        assertThat(left).containsExactlyElementsOf(failed.subList(2, 7).stream().map(FeedVersion::getId).toList());
        assertThat(statusInDb(current)).as("the cap never touches successful rows").isEqualTo("current");
        FeedVersion latest = versions.findLatestByFeedId().get(1L);
        assertThat(latest.getId()).isEqualTo(failed.get(6).getId());
        assertThat(FeedStatus.statusOf(versions.findCurrentByFeedId().get(1L), latest)).isEqualTo("failed");
    }

    @Test
    void fiveOrFewerFailedRowsAreAllKept() {
        for (int i = 0; i < 5; i++) {
            versionService.saveFailed(feed, source, Instant.now());
        }
        assertThat(countInDb("failed")).isEqualTo(5);
    }

    @Test
    void markCheckedOnlySetsCheckedAt() {
        FeedVersion current = versionService.saveAsCurrent(download(LocalDate.of(2027, 1, 1)), List.of());
        entityManager.flush();
        Instant checked = Instant.parse("2026-10-10T09:00:00Z");

        assertThat(versions.markChecked(current.getId(), checked)).isEqualTo(1);

        assertThat(jdbc.queryForObject("select checked_at from feeds.feed_version where id = ?",
                java.sql.Timestamp.class, current.getId()).toInstant()).isEqualTo(checked);
        assertThat(statusInDb(current)).isEqualTo("current");
    }
}
