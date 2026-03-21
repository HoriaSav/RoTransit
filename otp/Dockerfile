FROM opentripplanner/opentripplanner:latest

WORKDIR /var/opentripplanner

# Config
COPY build-config.json /var/opentripplanner/build-config.json
COPY otp-config.json /var/opentripplanner/otp-config.json
COPY router-config.json /var/opentripplanner/router-config.json

# GTFS/OSM data is mounted at runtime from ./otp volume.

EXPOSE 8080

# Build graph then serve
CMD ["--build", "--serve"]