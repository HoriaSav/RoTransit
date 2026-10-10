package com.example.RoTransit.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;

import java.time.Instant;
import java.time.LocalDate;

/**
 * One download attempt of a feed. At most one version per feed is "current" (the one we serve);
 * older successful ones are "old", failed attempts are "failed" and have no file.
 */
@Entity
public class FeedVersion {
    public static final String CURRENT = "current";
    public static final String UPCOMING = "upcoming"; // downloaded, but its timetable only starts later
    public static final String OLD = "old";
    public static final String FAILED = "failed";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "feed_id")
    private Feed feed;

    // nullable: a failed attempt may have no source, and deleting a source keeps its old versions
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "source_id")
    private FeedSource source;

    @JsonIgnore // never show server paths to clients, even if an entity is serialized by mistake
    private String filePath;
    private String sha256;
    private LocalDate startsOn;
    private LocalDate expiresOn;
    private Instant downloadedAt;
    private Instant servedFrom; // null = never was current
    private Instant checkedAt; // null = the source never sent this file again
    private String status;

    public Long getId() {
        return id;
    }

    public Feed getFeed() {
        return feed;
    }
    public void setFeed(Feed feed) {
        this.feed = feed;
    }

    public FeedSource getSource() {
        return source;
    }
    public void setSource(FeedSource source) {
        this.source = source;
    }

    public String getFilePath() {
        return filePath;
    }
    public void setFilePath(String filePath) {
        this.filePath = filePath;
    }

    public String getSha256() {
        return sha256;
    }
    public void setSha256(String sha256) {
        this.sha256 = sha256;
    }

    public LocalDate getStartsOn() {
        return startsOn;
    }
    public void setStartsOn(LocalDate startsOn) {
        this.startsOn = startsOn;
    }

    public LocalDate getExpiresOn() {
        return expiresOn;
    }
    public void setExpiresOn(LocalDate expiresOn) {
        this.expiresOn = expiresOn;
    }

    public Instant getDownloadedAt() {
        return downloadedAt;
    }
    public void setDownloadedAt(Instant downloadedAt) {
        this.downloadedAt = downloadedAt;
    }

    public Instant getServedFrom() {
        return servedFrom;
    }

    public void setServedFrom(Instant servedFrom) {
        this.servedFrom = servedFrom;
    }

    public Instant getCheckedAt() {
        return checkedAt;
    }

    public void setCheckedAt(Instant checkedAt) {
        this.checkedAt = checkedAt;
    }

    public String getStatus() {
        return status;
    }
    public void setStatus(String status) {
        this.status = status;
    }
}
