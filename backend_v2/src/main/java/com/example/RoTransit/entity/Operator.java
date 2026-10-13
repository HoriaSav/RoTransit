package com.example.RoTransit.entity;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;

/** A transit operator (one row of agency.txt) inside a downloaded feed version. */
@Entity
public class Operator {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "feed_version_id")
    private FeedVersion feedVersion;

    private String agencyId;
    private String name;
    private String url;

    public Long getId() {
        return id;
    }

    public FeedVersion getFeedVersion() {
        return feedVersion;
    }
    public void setFeedVersion(FeedVersion feedVersion) {
        this.feedVersion = feedVersion;
    }

    public String getAgencyId() {
        return agencyId;
    }
    public void setAgencyId(String agencyId) {
        this.agencyId = agencyId;
    }

    public String getName() {
        return name;
    }
    public void setName(String name) {
        this.name = name;
    }

    public String getUrl() {
        return url;
    }
    public void setUrl(String url) {
        this.url = url;
    }
}
