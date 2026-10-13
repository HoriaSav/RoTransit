#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DETACHED=0
BUILD=0
SKIP_SETUP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--detach) DETACHED=1; shift ;;
    --build) BUILD=1; shift ;;
    --skip-setup) SKIP_SETUP=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

cd "$REPO_ROOT"

if [[ "$SKIP_SETUP" -eq 0 ]]; then
  "$REPO_ROOT/scripts/server/setup.sh"
fi

args=(compose up)
if [[ "$DETACHED" -eq 1 ]]; then args+=(-d); fi
if [[ "$BUILD" -eq 1 ]]; then args+=(--build); fi

echo "Starting RoTransit stack (db, backend_v2 app on :8080, cloudflared)..."
docker "${args[@]}"
