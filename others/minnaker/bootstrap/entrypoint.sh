#!/bin/bash
# Bootstraps a disposable Spinnaker + Kayenta instance into the k3s cluster
# this container shares a network with, reproducing minnaker's install.sh
# (git clone spinnaker-kustomize-patches -> deploy.sh) without a bare VM.
#
# Every URL/version here is pinned and cross-checked against the actual
# upstream sources (not assumed) — see ../README.md for how to bump them.
set -euo pipefail

KUSTOMIZE_REF="50a095cd9aa1a83723f4cc09d6e5a78c6d96d17e"  # spinnaker-kustomize-patches@minnaker
OPERATOR_VERSION="1.8.11"   # armory-io/spinnaker-operator — matches our
                             # manifests' spinnaker.armory.io/v1alpha2 API
                             # group (NOT armory/spinnaker-operator, the OSS
                             # flavor, which registers spinnaker.io CRDs and
                             # would silently fail to recognize our CRs)
OPERATOR_NS="spinnaker-operator"
SPIN_NS="spinnaker"

log() { echo "[bootstrap] $*"; }

# k3s writes its kubeconfig with `server: https://127.0.0.1:6443`, which is
# correct on the k3s container itself but not for a sibling container on
# the same compose network — rewrite it to the k3s service's DNS name
# (compose service name "k3s", also passed via --tls-san on the server so
# the cert covers it). KUBECONFIG_SRC is the read-only mount of the file
# k3s wrote; KUBECONFIG (writable, container-local) is what kubectl uses.
if [ -n "${KUBECONFIG_SRC:-}" ]; then
  mkdir -p "$(dirname "$KUBECONFIG")"
  cp "$KUBECONFIG_SRC" "$KUBECONFIG"
  sed -i "s#https://127.0.0.1:6443#https://k3s:6443#" "$KUBECONFIG"
fi

wait_for() {
  local desc="$1" cmd="$2" attempts="${3:-60}" delay="${4:-5}"
  for i in $(seq 1 "$attempts"); do
    if eval "$cmd" >/dev/null 2>&1; then
      log "$desc: ready"
      return 0
    fi
    log "$desc: not ready yet (attempt $i/$attempts)"
    sleep "$delay"
  done
  log "ERROR: $desc did not become ready after $((attempts * delay))s"
  return 1
}

log "Waiting for k3s API server..."
wait_for "k3s API" "kubectl get nodes" 60 5

log "Fetching Spinnaker Operator v${OPERATOR_VERSION} (armory-io flavor)..."
rm -rf /tmp/operator && mkdir -p /tmp/operator
curl -sL "https://github.com/armory-io/spinnaker-operator/releases/download/v${OPERATOR_VERSION}/manifests.tgz" \
  | tar -xz -C /tmp/operator
kubectl apply -f /tmp/operator/deploy/crds/

log "Fetching operator kustomization from spinnaker-kustomize-patches@${KUSTOMIZE_REF}..."
mkdir -p /tmp/operator-kustomize
for f in kustomization.yml patch-config.yaml halyard-local.yml; do
  curl -sL "https://raw.githubusercontent.com/armory/spinnaker-kustomize-patches/${KUSTOMIZE_REF}/operator/${f}" \
    -o "/tmp/operator-kustomize/${f}"
done
# deploy.sh's own layout: the release tarball's deploy/ sits alongside the
# patches repo's operator/kustomization.yml, which references it by
# relative path (deploy/operator/cluster/...).
cp -r /tmp/operator/deploy /tmp/operator-kustomize/deploy

kubectl get ns "$OPERATOR_NS" >/dev/null 2>&1 || kubectl create ns "$OPERATOR_NS"
kubectl -n "$OPERATOR_NS" apply -k /tmp/operator-kustomize

log "Waiting for Spinnaker Operator deployment..."
wait_for "spinnaker-operator deployment" \
  "kubectl -n $OPERATOR_NS rollout status deployment/spinnaker-operator --timeout=10s" 30 10

log "Creating spin-secrets (disposable test values from upstream's sample file — not real credentials)..."
kubectl get ns "$SPIN_NS" >/dev/null 2>&1 || kubectl create ns "$SPIN_NS"
curl -sL "https://raw.githubusercontent.com/armory/spinnaker-kustomize-patches/${KUSTOMIZE_REF}/secrets/secrets-example.env" \
  -o /tmp/secrets.env
LITERAL_ARGS=()
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  LITERAL_ARGS+=("--from-literal=${line}")
done < /tmp/secrets.env
kubectl -n "$SPIN_NS" get secret spin-secrets >/dev/null 2>&1 \
  && kubectl -n "$SPIN_NS" delete secret spin-secrets
kubectl -n "$SPIN_NS" create secret generic spin-secrets "${LITERAL_ARGS[@]}"

# Two-pass apply: the SpinnakerService admission webhook validates that
# spin-sa (created by this same manifest set) has a token Secret — but on
# k8s 1.24+, ServiceAccounts no longer get one auto-created (this recipe
# predates that change). Chicken-and-egg on a fresh cluster: pass 1 creates
# spin-sa and everything else, failing only on SpinnakerService itself
# (kubectl apply -k continues past individual resource failures); we then
# create the token Secret spin-sa now exists for, and pass 2 succeeds.
# Confirmed necessary by an actual first-run failure, not assumed upfront.
log "Applying Spinnaker manifests, pass 1 (creates spin-sa; SpinnakerService validation may fail this pass)..."
kubectl -n "$SPIN_NS" apply -k /manifests || true

log "Ensuring spin-sa has a token Secret (k8s 1.24+ no longer auto-creates one)..."
if ! kubectl -n "$SPIN_NS" get secret spin-sa-token >/dev/null 2>&1; then
  kubectl -n "$SPIN_NS" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: spin-sa-token
  namespace: ${SPIN_NS}
  annotations:
    kubernetes.io/service-account.name: spin-sa
type: kubernetes.io/service-account-token
EOF
  sleep 5   # give the API server a moment to populate the token
fi

log "Applying Spinnaker manifests, pass 2 (should pass full validation now)..."
kubectl -n "$SPIN_NS" apply -k /manifests

log "Waiting for SpinnakerService to report healthy (status.status == OK)..."
# .status.status is a real field on the spinnaker.armory.io/v1alpha2
# SpinnakerService CRD (confirmed against the CRD's OpenAPI schema at
# OPERATOR_VERSION above) — not guessed from convention alone. What
# populates it as exactly "OK" vs some other string on success has NOT been
# confirmed against a live cluster; if this loop times out but pods look
# healthy via `kubectl -n spinnaker get pods`, that's the first thing to
# check against a real run.
for i in $(seq 1 60); do
  STATUS="$(kubectl -n "$SPIN_NS" get spinsvc spinnaker -o jsonpath='{.status.status}' 2>/dev/null || true)"
  if [ "$STATUS" = "OK" ]; then
    log "SpinnakerService is healthy"
    exit 0
  fi
  log "SpinnakerService status: ${STATUS:-<none yet>} (attempt $i/60)"
  sleep 10
done

log "ERROR: SpinnakerService did not report healthy in time"
kubectl -n "$SPIN_NS" get spinsvc spinnaker -o yaml || true
kubectl -n "$SPIN_NS" get pods || true
exit 1
