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
        FeedVersion saved = versions.save(version);
        for (Operator operator : newOperators) {
            operator.setFeedVersion(saved);
        }
        operators.saveAll(newOperators);
        return saved;
    }

    /** Records a failed attempt as its own row. The current version is not touched, so it keeps being served. */
    public FeedVersion saveFailed(Feed feed, FeedSource source, Instant attemptedAt) {
        FeedVersion failed = new FeedVersion();
        failed.setFeed(feed);
        failed.setSource(source);
        failed.setDownloadedAt(attemptedAt);
        failed.setStatus(FeedVersion.FAILED);
        return versions.save(failed);
    }
}
