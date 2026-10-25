#!/usr/bin/env bash
set -euo pipefail

server_id="${JFROG_SERVER_ID:-workshop}"
platform_url="${JFROG_PLATFORM_URL:-${JFROG_URL:-}}"

if [ -z "$platform_url" ]; then
  echo "[JFrog] ERROR: JFROG_PLATFORM_URL or JFROG_URL is not set."
  exit 1
fi

if [ -z "${JFROG_ACCESS_TOKEN:-}" ]; then
  echo "[JFrog] ERROR: JFROG_ACCESS_TOKEN is not set."
  exit 1
fi

# Accept either https://host or host, and remove any trailing path.
platform_url="${platform_url#http://}"
platform_url="${platform_url#https://}"
platform_url="https://${platform_url%%/*}"

echo "[JFrog] Syncing server '${server_id}' to ${platform_url}..."
printf '%s' "$JFROG_ACCESS_TOKEN" | jf config add "$server_id" \
  --url "$platform_url" \
  --access-token-stdin \
  --interactive=false \
  --overwrite

jf config use "$server_id"
jf rt ping --server-id "$server_id"
echo "[JFrog] Server configuration is up to date."
