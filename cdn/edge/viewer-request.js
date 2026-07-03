// CloudFront Function — viewer-request
//
// Decides stable vs. canary for this request, sticky per visitor via a
// cookie. Reads the release manifest from a CloudFront KeyValueStore (not
// Lambda@Edge — Functions + KVS avoid Lambda cold-start latency and are
// cheap enough to run on every request).
//
// One CloudFront Function *resource* per app is published from this same
// source (APP baked in at publish time — see cdn/README.md), because a
// KVS-backed Function can't take deploy-time params otherwise.
//
// KVS keys (written by cdn/scripts/shift-canary.sh and promote.sh),
// namespaced per app since both apps share one KeyValueStore:
//   <app>.stableVersion   e.g. "a1b2c3d"
//   <app>.canaryVersion   e.g. "e4f5g6h" (== stable when no canary is live)
//   <app>.canaryWeight    "0".."100" — percent of *new* visitors -> canary
//
// The decision is written to a custom header so viewer-response.js can set
// a matching cookie without recomputing anything (CloudFront guarantees
// both functions see the same request/response cycle).

import cf from 'cloudfront';

const APP = '__APP_NAME__'; // replaced at publish time, see cdn/README.md
const kvsHandle = cf.kvs('<CLOUDFRONT_KVS_ARN>');

function handler(event) {
  const request = event.request;
  const cookies = request.cookies || {};
  const stableVersion = kvsHandle.get(`${APP}.stableVersion`, { fallback: 'unknown' });
  const canaryVersion = kvsHandle.get(`${APP}.canaryVersion`, { fallback: stableVersion });
  const canaryWeight = parseInt(kvsHandle.get(`${APP}.canaryWeight`, { fallback: '0' }), 10);

  let bucket = 'stable';
  if (cookies['app-bucket'] && cookies['app-bucket'].value === 'canary' && canaryWeight > 0) {
    bucket = 'canary';
  } else if (!cookies['app-bucket']) {
    bucket = Math.random() * 100 < canaryWeight ? 'canary' : 'stable';
  }

  const version = bucket === 'canary' ? canaryVersion : stableVersion;

  // rewrite /some/path -> /releases/<version>/some/path
  request.uri = `/releases/${version}${request.uri === '/' ? '/index.html' : request.uri}`;

  request.headers['x-app-bucket-decision'] = { value: bucket };
  return request;
}
