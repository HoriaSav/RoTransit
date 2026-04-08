#!/bin/sh
set -e

GRAPH_BASE="/var/opentripplanner"

if [ -f "$GRAPH_BASE/graph.obj" ] || [ -f "$GRAPH_BASE/graph/Graph.obj" ] || [ -f "$GRAPH_BASE/graph/graph.obj" ]; then
  exec /docker-entrypoint.sh --load --serve
fi

exec /docker-entrypoint.sh --build --save --serve
