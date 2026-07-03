#!/usr/bin/env bash
# Cloudflare Pages deployments are immutable/unique per URL, so there's
# nothing to invalidate there. What *can* be stale is Cloudflare's edge
# cache for the custom domain the canary-router Worker sits on (e.g. a
# cached index.html) — purge that explicitly after a promote.
#
# Usage: invalidate.sh <app>
set -euo pipefail

APP="$1"

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN env var required}"
: "${CF_ZONE_ID:?CF_ZONE_ID env var required}"
: "${APP_DOMAIN:?APP_DOMAIN env var required (the custom domain for this app, e.g. app.example.com)}"

curl -sf -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{\"files\": [\"https://${APP_DOMAIN}/\", \"https://${APP_DOMAIN}/index.html\"]}"

echo "${APP}: edge cache purge requested for ${APP_DOMAIN}"
