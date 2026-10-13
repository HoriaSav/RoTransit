package com.example.RoTransit.dto;

/** One operator name of a feed's current version (result row of OperatorRepository.findCurrentOperatorNames). */
public record FeedOperator(Long feedId, String name) {
}
