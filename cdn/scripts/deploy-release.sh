#!/usr/bin/env bash
# Uploads a build to an immutable, versioned S3 prefix. Does NOT change
# what any visitor sees — that only happens in shift-canary.sh / promote.sh.
#
# Usage: deploy-release.sh <app> <version> <dist-dir>
set -euo pipefail

APP="$1"           # frontend | micro-frontend
VERSION="$2"        # git sha or tag
DIST_DIR="$3"       # local build output, e.g. apps/frontend/dist
BUCKET="${CDN_BUCKET:?CDN_BUCKET env var required}"

aws s3 sync "$DIST_DIR" "s3://${BUCKET}/${APP}/releases/${VERSION}/" \
  --delete \
  --cache-control "public,max-age=31536000,immutable"

echo "Uploaded ${APP}@${VERSION} to s3://${BUCKET}/${APP}/releases/${VERSION}/"
