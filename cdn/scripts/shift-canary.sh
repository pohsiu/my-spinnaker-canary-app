#!/usr/bin/env bash
# Points the KVS "canaryVersion" key at a new release and sets what percent
# of new visitors get routed to it. Existing stable traffic is untouched.
#
# Usage: shift-canary.sh <app> <version> <weight-percent>
set -euo pipefail

APP="$1"
VERSION="$2"
WEIGHT="$3"          # 0-100
KVS_ARN="${CLOUDFRONT_KVS_ARN:?CLOUDFRONT_KVS_ARN env var required}"

aws cloudfront-keyvaluestore update-keys \
  --kvs-arn "$KVS_ARN" \
  --if-match "$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn "$KVS_ARN" --query 'ETag' --output text)" \
  --puts "[
    {\"Key\": \"${APP}.canaryVersion\", \"Value\": \"${VERSION}\"},
    {\"Key\": \"${APP}.canaryWeight\", \"Value\": \"${WEIGHT}\"}
  ]"

echo "${APP}: canary=${VERSION} at ${WEIGHT}% of new visitors"
