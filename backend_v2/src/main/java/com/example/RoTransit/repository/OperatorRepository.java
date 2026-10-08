package com.example.RoTransit.repository;

import com.example.RoTransit.dto.FeedOperator;
import com.example.RoTransit.entity.Operator;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface OperatorRepository extends JpaRepository<Operator, Long> {

    /** Operator names of every feed's current version, in one query (feed id + name only, no entities). */
    @Query("select new com.example.RoTransit.dto.FeedOperator(v.feed.id, o.name) from Operator o join o.feedVersion v"
            + " where v.status = 'current' order by o.id")
    List<FeedOperator> findCurrentOperatorNames();
}
