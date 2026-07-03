FROM alpine:3.20

# git is required by `kubectl apply -k` to fetch remote kustomize bases
# (github.com/... URLs in manifests/kustomization.yml) — found missing at
# actual runtime, not caught by `docker compose config` or `kubectl
# kustomize` run on the host (which had git available locally).
RUN apk add --no-cache bash curl tar git

ARG KUBECTL_VERSION=v1.32.7
RUN curl -sLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')/kubectl" \
    && chmod +x /usr/local/bin/kubectl

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
