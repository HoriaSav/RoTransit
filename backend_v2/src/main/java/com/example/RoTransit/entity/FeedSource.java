package com.example.RoTransit.entity;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;

/** Where a feed can be downloaded from. Priority 1 is the one used today. */
@Entity
public class FeedSource {
    public static final String MOBILITYDB = "mobilitydb";
    public static final String URL = "url";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "feed_id")
    private Feed feed;

    private String kind;
    private String ref;
    private int priority;

    /** The URL to download: a Mobility Database id is turned into its latest.zip URL, a url source is used as is. */
    public String downloadUrl() {
        if (MOBILITYDB.equals(kind)) {
            return "https://files.mobilitydatabase.org/" + ref + "/latest.zip";
        }
        return ref;
    }

    public Long getId() {
        return id;
    }

    public Feed getFeed() {
        return feed;
    }
    public void setFeed(Feed feed) {
        this.feed = feed;
    }

    public String getKind() {
        return kind;
    }
    public void setKind(String kind) {
        this.kind = kind;
    }

    public String getRef() {
        return ref;
    }
    public void setRef(String ref) {
        this.ref = ref;
    }

    public int getPriority() {
        return priority;
    }
    public void setPriority(int priority) {
        this.priority = priority;
    }
}
