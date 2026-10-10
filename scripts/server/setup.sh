#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKIP_TUNNEL_TOKEN_CHECK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-tunnel-token-check) SKIP_TUNNEL_TOKEN_CHECK=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

ensure_env_file() {
  local example_path="$1"
  local target_path="$2"
  local label="$3"

  if [[ -f "$target_path" ]]; then
    echo "[ok] ${label} exists: ${target_path}"
    return
  fi

  if [[ ! -f "$example_path" ]]; then
    echo "Missing example file: ${example_path}" >&2
    exit 1
  fi

  cp "$example_path" "$target_path"
  echo "[created] ${label} from example: ${target_path}"
}

tunnel_token_ok() {
  local env_path="$1"
  local token
  token="$(grep -E '^TUNNEL_TOKEN=' "$env_path" | head -n1 | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs || true)"

  if [[ -n "$token" && "$token" != "eyJ..." && ${#token} -gt 20 ]]; then
    echo "[ok] Cloudflare tunnel token is set"
    return 0
  fi

  echo "[action] Edit cloudflare/.env and set TUNNEL_TOKEN from Zero Trust -> Tunnels -> rotransit-home"
  return 1
}

cd "$REPO_ROOT"
echo "RoTransit server setup (repo root: $REPO_ROOT)"

ensure_env_file "$REPO_ROOT/db/postgres/.env.example" "$REPO_ROOT/db/postgres/.env" "Postgres env"
ensure_env_file "$REPO_ROOT/cloudflare/.env.example" "$REPO_ROOT/cloudflare/.env" "Cloudflare env"

ensure_env_file "$REPO_ROOT/backend_v2/.env.example" "$REPO_ROOT/backend_v2/.env" "Backend env"

for var in SPRING_DATASOURCE_PASSWORD SPRING_SECURITY_PASSWORD; do
  if ! grep -Eq "^${var}=.+" "$REPO_ROOT/backend_v2/.env"; then
    echo "[action] Set ${var} in backend_v2/.env (see backend_v2/README.md, Run locally)" >&2
    exit 1
  fi
done
echo "[ok] backend_v2/.env has both passwords set"

docker compose version >/dev/null
echo "[ok] Docker Compose is available"

if [[ "$SKIP_TUNNEL_TOKEN_CHECK" -eq 0 ]]; then
  tunnel_token_ok "$REPO_ROOT/cloudflare/.env" || exit 1
fi

echo ""
echo "Setup complete. Start the stack (db, app on :8080, cloudflared) with:"
echo "  ./scripts/server/up.sh"
echo ""
echo "In Cloudflare (Zero Trust -> Tunnels -> rotransit-home -> Public hostname) api.horiasavin.me must target http://app:8080,"
echo "and /admin/* should be blocked by a Cloudflare Access policy."
echo "Public API (after cloudflared is running): https://api.horiasavin.me/api/feeds"
echo "Flutter: flutter run --dart-define=API_BASE_URL=https://api.horiasavin.me"
