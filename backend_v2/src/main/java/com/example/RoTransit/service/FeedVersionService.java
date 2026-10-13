package com.example.RoTransit.service;

import com.example.RoTransit.entity.Feed;
import com.example.RoTransit.entity.FeedSource;
import com.example.RoTransit.entity.FeedVersion;
import com.example.RoTransit.entity.Operator;
import com.example.RoTransit.repository.FeedVersionRepository;
import com.example.RoTransit.repository.OperatorRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

/**
 * Writes feed_version rows. It is its own bean (not part of FeedService) because @Transactional only works when
 * the method is called from another bean: Spring wraps the bean in a proxy, and a call inside the same class
 * would skip that proxy and run without a transaction.
 */
@Service
public class FeedVersionService {
    private final FeedVersionRepository versions;
    private final OperatorRepository operators;

    public FeedVersionService(FeedVersionRepository versions, OperatorRepository operators) {
        this.versions = versions;
        this.operators = operators;
    }

    /**
     * Makes a freshly downloaded version the current one, in one transaction: the old current version becomes
     * "old", the new one is saved as "current" together with its operators. If anything fails, all of it is
     * rolled back and the old version stays current.
     */
    @Transactional
    public FeedVersion saveAsCurrent(FeedVersion version, List<Operator> newOperators) {
        // demote first: the database allows only one current version per feed (unique index in V1)
        versions.markCurrentAsOld(version.getFeed().getId());
        version.setStatus(FeedVersion.CURRENT);
        version.setServedFrom(Instant.now()); // remembered after it becomes old, for retention
        FeedVersion saved = versions.save(version);
        for (Operator operator : newOperators) {
            operator.setFeedVersion(saved);
        }
        operators.saveAll(newOperators);
        return saved;
    }

    /**
     * Saves a downloaded version whose timetable starts in the future as "upcoming". The current version is not
     * touched. A previous upcoming version is replaced (it becomes "old"): the source has published something newer.
     */
    @Transactional
    public FeedVersion saveAsUpcoming(FeedVersion version, List<Operator> newOperators) {
        // demote first: the database allows only one upcoming version per feed (unique index in V1)
        versions.markUpcomingAsOld(version.getFeed().getId());
        version.setStatus(FeedVersion.UPCOMING);
        FeedVersion saved = versions.save(version);
        for (Operator operator : newOperators) {
            operator.setFeedVersion(saved);
        }
        operators.saveAll(newOperators);
        return saved;
    }

    /**
     * Makes the feed's upcoming version the current one, in one transaction: current becomes "old", upcoming becomes
     * "current". Empty if the feed has no upcoming version.
     */
    @Transactional
    public Optional<FeedVersion> promoteUpcoming(Long feedId) {
        Optional<FeedVersion> upcoming = versions.findByFeedIdAndStatus(feedId, FeedVersion.UPCOMING);
        upcoming.ifPresent(version -> {
            // the bulk update runs right away; the status change below is written when the transaction commits,
            // so there is never a moment with two current rows
            versions.markCurrentAsOld(feedId);
            version.setStatus(FeedVersion.CURRENT);
            version.setServedFrom(Instant.now());
            versions.save(version);
        });
        return upcoming;
    }

    /** Records a failed attempt as its own row. The current version is not touched, so it keeps being served. */
    public FeedVersion saveFailed(Feed feed, FeedSource source, Instant attemptedAt) {
        FeedVersion failed = new FeedVersion();
        failed.setFeed(feed);
        failed.setSource(source);
        failed.setDownloadedAt(attemptedAt);
        failed.setStatus(FeedVersion.FAILED);
        FeedVersion saved = versions.save(failed);
        // a feed that fails every night would collect a row per night forever; the newest few are enough to see what
        // happened. The newest one always stays, so the admin list still says "failed".
        List<FeedVersion> allFailed = versions.findByFeedIdAndStatusOrderByIdDesc(feed.getId(), FeedVersion.FAILED);
        if (allFailed.size() > FAILED_ROWS_KEPT) {
            versions.deleteAll(allFailed.subList(FAILED_ROWS_KEPT, allFailed.size()));
        }
        return saved;
    }

    /** How many failed attempts per feed are kept. */
    static final int FAILED_ROWS_KEPT = 5;
}
