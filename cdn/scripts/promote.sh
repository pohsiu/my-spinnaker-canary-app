#!/usr/bin/env bash
# Cuts stable over to the version that's currently the canary, and zeroes
# the canary weight. This is the only script that changes what 100% of
# *existing* stable visitors see — everything before this point only
# affected the opt-in canary slice.
#
# Usage: promote.sh <app> <version>
set -euo pipefail

APP="$1"
VERSION="$2"
KVS_ARN="${CLOUDFRONT_KVS_ARN:?CLOUDFRONT_KVS_ARN env var required}"

aws cloudfront-keyvaluestore update-keys \
  --kvs-arn "$KVS_ARN" \
  --if-match "$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn "$KVS_ARN" --query 'ETag' --output text)" \
  --puts "[
    {\"Key\": \"${APP}.stableVersion\", \"Value\": \"${VERSION}\"},
    {\"Key\": \"${APP}.canaryVersion\", \"Value\": \"${VERSION}\"},
    {\"Key\": \"${APP}.canaryWeight\", \"Value\": \"0\"}
  ]"

echo "${APP}: promoted ${VERSION} to stable (100%)"
