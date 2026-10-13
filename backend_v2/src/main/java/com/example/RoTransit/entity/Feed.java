package com.example.RoTransit.entity;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;

/** A GTFS dataset served for a city. Its files live in FeedVersion, where to get them in FeedSource. */
@Entity
public class Feed {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // LAZY: the city is only loaded when it is used. Lists load it up front with an @EntityGraph (FeedRepository).
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "city_id")
    private City city;

    private String name;

    public Long getId() {
        return id;
    }

    public City getCity() {
        return city;
    }
    public void setCity(City city) {
        this.city = city;
    }

    public String getCityName() {
        return city.getName();
    }

    public String getName() {
        return name;
    }
    public void setName(String name) {
        this.name = name;
    }
}
