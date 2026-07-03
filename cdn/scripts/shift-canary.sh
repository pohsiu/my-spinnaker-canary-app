#!/usr/bin/env bash
# Points the canary router's KV "canaryUrl" at a new deployment and sets
# what percent of new visitors get routed to it. Existing stable traffic
# is untouched.
#
# Usage: shift-canary.sh <app> <deployment-url> <weight-percent>
set -euo pipefail

APP="$1"
DEPLOYMENT_URL="$2"
WEIGHT="$3"          # 0-100

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN env var required}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID env var required}"
: "${CF_KV_NAMESPACE_ID:?CF_KV_NAMESPACE_ID env var required}"

npx --yes wrangler kv key put "${APP}.canaryUrl" "$DEPLOYMENT_URL" \
  --namespace-id "$CF_KV_NAMESPACE_ID" --remote
npx --yes wrangler kv key put "${APP}.canaryWeight" "$WEIGHT" \
  --namespace-id "$CF_KV_NAMESPACE_ID" --remote

echo "${APP}: canary=${DEPLOYMENT_URL} at ${WEIGHT}% of new visitors"
