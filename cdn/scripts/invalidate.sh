#!/usr/bin/env bash
# KVS reads are near-instant (no invalidation needed for the routing
# decision itself), but browsers/proxies may have cached index.html with
# short TTLs — invalidate it explicitly after a promote so nobody is stuck
# on a stale entry point.
#
# Usage: invalidate.sh <app>
set -euo pipefail

APP="$1"
DIST_ID="${CLOUDFRONT_DISTRIBUTION_ID:?CLOUDFRONT_DISTRIBUTION_ID env var required}"

aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "/${APP}/*"

echo "${APP}: invalidation requested"
