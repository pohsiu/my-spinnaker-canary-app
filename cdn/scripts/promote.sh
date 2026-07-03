#!/usr/bin/env bash
# Cuts stable over to the deployment that's currently the canary, and
# zeroes the canary weight. This is the only script that changes what
# 100% of *existing* stable visitors see — everything before this point
# only affected the opt-in canary slice.
#
# Usage: promote.sh <app> <deployment-url>
set -euo pipefail

APP="$1"
DEPLOYMENT_URL="$2"

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN env var required}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID env var required}"
: "${CF_KV_NAMESPACE_ID:?CF_KV_NAMESPACE_ID env var required}"

npx --yes wrangler kv key put "${APP}.stableUrl" "$DEPLOYMENT_URL" \
  --namespace-id "$CF_KV_NAMESPACE_ID" --remote
npx --yes wrangler kv key put "${APP}.canaryUrl" "$DEPLOYMENT_URL" \
  --namespace-id "$CF_KV_NAMESPACE_ID" --remote
npx --yes wrangler kv key put "${APP}.canaryWeight" "0" \
  --namespace-id "$CF_KV_NAMESPACE_ID" --remote

echo "${APP}: promoted ${DEPLOYMENT_URL} to stable (100%)"
