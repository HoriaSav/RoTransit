# Build stage: uses the Maven wrapper's pinned Maven via the official image
FROM maven:3.9.9-eclipse-temurin-21 AS builder
WORKDIR /app

COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline

COPY src ./src
RUN mvn -q -DskipTests clean package

# Runtime stage: JRE only, non-root user
FROM eclipse-temurin:21-jre
WORKDIR /app

RUN groupadd --system rotransit && useradd --system --gid rotransit --home-dir /app rotransit \
    && mkdir -p /app/feeds && chown rotransit:rotransit /app/feeds

COPY --from=builder /app/target/*.jar app.jar

USER rotransit

# Downloaded GTFS files live in /app/feeds (FeedService.FEEDS_ROOT is relative to the working dir)
VOLUME ["/app/feeds"]

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
