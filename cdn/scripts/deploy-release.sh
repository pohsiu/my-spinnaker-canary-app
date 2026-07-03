#!/usr/bin/env bash
# Uploads a build as a new Cloudflare Pages deployment. Cloudflare gives
# every deployment its own permanent URL automatically — this does NOT
# change what any visitor sees (the canary router isn't pointed at it yet),
# unlike the S3 version this replaced there's no manual "versioned prefix"
# bookkeeping needed.
#
# Usage: deploy-release.sh <app> <version> <dist-dir>
# Prints the deployment URL on stdout (last line) for the caller to capture.
set -euo pipefail

APP="$1"           # frontend | micro-frontend
VERSION="$2"        # git sha or tag, used as the Pages branch name
DIST_DIR="$3"       # local build output, e.g. apps/frontend/dist
PROJECT="my-spinnaker-canary-app-${APP}"

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN env var required}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID env var required}"

DEPLOY_OUTPUT=$(npx --yes wrangler pages deploy "$DIST_DIR" \
  --project-name="$PROJECT" \
  --branch="$VERSION" \
  --commit-hash="$VERSION")

echo "$DEPLOY_OUTPUT" >&2
DEPLOYMENT_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[a-z0-9.-]+\.pages\.dev' | head -1)

if [ -z "$DEPLOYMENT_URL" ]; then
  echo "Could not parse deployment URL from wrangler output" >&2
  exit 1
fi

echo "$DEPLOYMENT_URL"
