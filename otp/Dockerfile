FROM opentripplanner/opentripplanner:2.9.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/opentripplanner

# Config
COPY build-config.json /var/opentripplanner/build-config.json
COPY otp-config.json /var/opentripplanner/otp-config.json
COPY router-config.json /var/opentripplanner/router-config.json
COPY start-otp.sh /usr/local/bin/start-otp.sh
RUN sed -i 's/\r$//' /usr/local/bin/start-otp.sh && chmod +x /usr/local/bin/start-otp.sh

# GTFS/OSM data is mounted at runtime from ./otp volume.

EXPOSE 8080

# Load saved graph when present; otherwise build+save then serve.
ENTRYPOINT ["sh", "/usr/local/bin/start-otp.sh"]